import 'dart:io' show Process, Socket;

import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wsl2distromanager/api/ai_workspace/service.dart';
import 'package:wsl2distromanager/api/execution/broker.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/components/notify.dart';

import 'mocks.dart';

/// A real bash for the probe-script tests below, or null when none is
/// installed on this machine.
///
/// The status probes are bash *programs* assembled from string fragments, and
/// every status bug this file guards against was a defect in that program
/// rather than in the Dart around it: `[ -d "~/.hermes" ]` never matched
/// because `~` does not expand inside double quotes, and `grep -q 18789` also
/// matched `:187890`. A mock shell handing back a canned `running` cannot see
/// either. Prefers Git Bash, but WSL's `bash.exe` works too — the scripts are
/// POSIX-only and reference no host paths.
String? _locateBash() {
  const candidates = [
    r'C:\Program Files\Git\bin\bash.exe',
    r'C:\Program Files (x86)\Git\bin\bash.exe',
    'bash',
  ];
  for (final candidate in candidates) {
    try {
      if (Process.runSync(candidate, ['-c', 'echo ok']).exitCode == 0) {
        return candidate;
      }
    } catch (_) {
      // Not on this machine — try the next candidate.
    }
  }
  return null;
}

final String? _bash = _locateBash();

/// Runs [script] — the exact string the service sends into the distro — under
/// a real bash, with [prelude]'s shell functions standing in for the distro's
/// commands. Functions take precedence over `PATH` lookups, so no temporary
/// directory or `PATH` juggling is needed.
Future<String> _runProbeScript(String prelude, String script) async {
  final result = await Process.run(_bash!, ['-c', '$prelude$script']);
  return (result.stdout as String).trim();
}

/// True when something on this machine really is listening on [port].
///
/// The gateway probe's `/dev/tcp` fallback makes a genuine connection attempt,
/// so a "nothing is listening" case cannot be asserted while a real service
/// holds the port.
Future<bool> _hostPortIsOpen(int port) async {
  try {
    final socket = await Socket.connect('127.0.0.1', port,
        timeout: const Duration(milliseconds: 200));
    socket.destroy();
    return true;
  } catch (_) {
    return false;
  }
}

void main() {
  group('AiWorkspaceService', () {
    late TestShell testShell;
    late ExecutionBroker broker;
    late AiWorkspaceService service;
    // Recorded rather than swallowed: the toast is the loudest thing on the
    // screen, so which one a lifecycle call raises is behaviour worth testing.
    final notifications = <String>[];

    setUpAll(() {
      Notify();
      Notify.message = (msg,
          {duration, loading = false, useWidget = false, leadingIcon = true, dynamic widget}) {
        notifications.add(msg);
      };
    });

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      testShell = TestShell();
      broker = ExecutionBroker(shell: testShell);
      // Default to "always reachable" so getDashboardUrl tests don't hit a
      // real HTTP stack — individual tests override this where they
      // specifically want to exercise unreachable/timeout behavior.
      service = AiWorkspaceService(
        broker: broker,
        reachabilityChecker: (_) async => true,
      );
    });

    tearDown(() {
      testShell.reset();
      notifications.clear();
    });

    group('ensureDistro', () {
      test('marks distro ready when it already exists', () async {
        // wsl --list --quiet returns the ai-workspace distro name
        testShell.stdoutData = 'Alpine\nai-workspace\nUbuntu';
        await service.ensureDistro();

        expect(testShell.lastCommand, ['wsl', '--list', '--quiet']);
      });

      test('attempts to install Ubuntu when distro missing', () async {
        // wsl --list --quiet returns no ai-workspace
        testShell.stdoutData = 'Alpine\nUbuntu';
        await service.ensureDistro();

        // Should have tried to install on the second wsl --install call
        expect(
          testShell.allCommands.any((cmd) => cmd.contains('--install')),
          true,
          reason: 'Should attempt to install Ubuntu',
        );
      });
    });

    group('init', () {
      test('initializes all tool states and probes status', () async {
        // Distro check succeeds immediately (first call)
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        expect(service.toolStates.length, AiWorkspaceTool.values.length);
        for (final tool in AiWorkspaceTool.values) {
          expect(service.getState(tool), isNotNull);
        }
      });

      test('probes all three tools with one wsl call each, not two',
          () async {
        // 1 distro list check + 1 status call per tool = 4 total, down from
        // up to 7 (1 + up to 2 per tool) before the status+existence checks
        // were combined into a single shell invocation.
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        expect(testShell.allCommands.length, 4);
      });
    });

    group('ensureInitialized', () {
      // Regression: the AI Workspace screen used to construct its own
      // AiWorkspaceService and do these checks only once the user navigated
      // there. Now app startup kicks this off in the background via a
      // shared instance, so the screen can skip straight to already-known
      // state — that only works if repeated calls don't redo the work.
      test('seeds state, ensures the distro, and checks every tool',
          () async {
        testShell.stdoutData = 'ai-workspace';

        await service.ensureInitialized();

        expect(service.toolStates.length, AiWorkspaceTool.values.length);
        for (final tool in AiWorkspaceTool.values) {
          expect(service.getState(tool)?.checked, true);
        }
      });

      test('is memoized — a second call does not repeat the WSL round trips',
          () async {
        testShell.stdoutData = 'ai-workspace';

        await service.ensureInitialized();
        final commandCountAfterFirstCall = testShell.allCommands.length;
        await service.ensureInitialized();

        expect(testShell.allCommands.length, commandCountAfterFirstCall);
      });

      test('a caller that awaits it while already in flight joins the same '
          'work instead of starting a duplicate', () async {
        testShell.stdoutData = 'ai-workspace';
        testShell.artificialDelay = const Duration(milliseconds: 50);

        final first = service.ensureInitialized();
        final second = service.ensureInitialized();
        await Future.wait([first, second]);

        // 1 distro list check + 1 status call per tool, exactly as a single
        // caller would produce — not doubled.
        expect(testShell.allCommands.length, 4);
      });
    });

    group('persisted status cache', () {
      test('seedToolStates() has nothing to show before any check has ever '
          'run', () {
        service.seedToolStates();

        for (final tool in AiWorkspaceTool.values) {
          expect(service.getState(tool)?.status, ToolStatus.notInstalled);
          expect(service.getState(tool)?.hasKnownStatus, false);
        }
      });

      test('a confirmed refreshStatus() result is cached for the next '
          'AiWorkspaceService instance (simulating an app restart)',
          () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        testShell.stdoutData = 'running';
        await service.refreshStatus(AiWorkspaceTool.openWebUi);

        // A brand new instance — same prefs, no shared in-memory state —
        // stands in for the app being relaunched.
        final restarted = AiWorkspaceService(broker: broker);
        restarted.seedToolStates();

        final state = restarted.getState(AiWorkspaceTool.openWebUi)!;
        expect(state.status, ToolStatus.running);
        expect(state.hasKnownStatus, true);
        // Not checked yet *this session* — a live refresh is still owed,
        // even though there's already something real to show.
        expect(state.checked, false);
      });

      test('a cached tool still gets a real background refresh, it just '
          "doesn't need to block the UI on it first", () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();
        testShell.stdoutData = 'exists';
        await service.refreshStatus(AiWorkspaceTool.hermesAgent);

        final restarted = AiWorkspaceService(broker: broker);
        restarted.seedToolStates();
        expect(restarted.getState(AiWorkspaceTool.hermesAgent)?.checked, false);

        await restarted.ensureInitialized();

        expect(restarted.getState(AiWorkspaceTool.hermesAgent)?.checked, true);
      });

      test('a shell-level failure does not overwrite good cached data',
          () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();
        testShell.stdoutData = 'running';
        await service.refreshStatus(AiWorkspaceTool.openWebUi);

        // Simulate a transient WSL hiccup on the next check. (ExecutionBroker
        // itself never lets this propagate as a raw exception — it always
        // converts a shell-level failure into a failed ExecutionResult — so
        // this exercises the same "not a confirmed signal" branch as a
        // plain non-zero exit code, just via a different trigger.)
        testShell.throwOnRun = true;
        await service.refreshStatus(AiWorkspaceTool.openWebUi);

        // In-memory state for *this* session reflects the failed attempt...
        expect(
          service.getState(AiWorkspaceTool.openWebUi)?.status,
          ToolStatus.error,
        );
        // ...but the cache a future launch would read from still has the
        // last genuinely confirmed answer, not the transient failure.
        final restarted = AiWorkspaceService(broker: broker);
        restarted.seedToolStates();
        expect(
          restarted.getState(AiWorkspaceTool.openWebUi)?.status,
          ToolStatus.running,
        );
      });

      test('a generic (non-distro-missing) command failure does not '
          'overwrite good cached data', () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();
        testShell.stdoutData = 'running';
        await service.refreshStatus(AiWorkspaceTool.openWebUi);

        testShell.exitCode = 1;
        testShell.stderrData = 'some transient docker error';
        await service.refreshStatus(AiWorkspaceTool.openWebUi);

        final restarted = AiWorkspaceService(broker: broker);
        restarted.seedToolStates();
        expect(
          restarted.getState(AiWorkspaceTool.openWebUi)?.status,
          ToolStatus.running,
        );
      });

      test('install() success is cached immediately, without waiting for a '
          'follow-up refreshStatus()', () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        testShell.exitCode = 0;
        await service.install(AiWorkspaceTool.hermesAgent);

        final restarted = AiWorkspaceService(broker: broker);
        restarted.seedToolStates();
        expect(
          restarted.getState(AiWorkspaceTool.hermesAgent)?.status,
          ToolStatus.stopped,
        );
      });

      test('start() success is cached', () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();
        service.getState(AiWorkspaceTool.hermesAgent)!.status =
            ToolStatus.stopped;

        testShell.exitCode = 0;
        await service.start(AiWorkspaceTool.hermesAgent);

        final restarted = AiWorkspaceService(broker: broker);
        restarted.seedToolStates();
        expect(
          restarted.getState(AiWorkspaceTool.hermesAgent)?.status,
          ToolStatus.running,
        );
      });

      test('stop() success is cached', () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();
        service.getState(AiWorkspaceTool.hermesAgent)!.status =
            ToolStatus.running;

        testShell.exitCode = 0;
        await service.stop(AiWorkspaceTool.hermesAgent);

        final restarted = AiWorkspaceService(broker: broker);
        restarted.seedToolStates();
        expect(
          restarted.getState(AiWorkspaceTool.hermesAgent)?.status,
          ToolStatus.stopped,
        );
      });
    });

    group('install', () {
      test('installs hermes agent successfully', () async {
        // First call: ensureDistro list check. Tool states init via init().
        testShell.stdoutData = 'ai-workspace';
        await service.init(); // initializes tool states + consumes distro check

        // Now install should work — the wsl command for install goes through broker
        testShell.exitCode = 0;
        final result = await service.install(AiWorkspaceTool.hermesAgent);

        expect(result, true);
        expect(
          service.getState(AiWorkspaceTool.hermesAgent)?.status,
          ToolStatus.stopped,
        );
      });

      test('returns false and sets error on install failure', () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        testShell.exitCode = 1;
        testShell.stderrData = 'curl failed';

        final result = await service.install(AiWorkspaceTool.openClaw);

        expect(result, false);
        expect(
          service.getState(AiWorkspaceTool.openClaw)?.status,
          ToolStatus.error,
        );
        expect(
          service.getState(AiWorkspaceTool.openClaw)?.errorMessage,
          contains('curl failed'),
        );
      });

      test('a failed install keeps its error and message across a background '
          'refresh', () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        testShell.exitCode = 1;
        testShell.stderrData = 'curl failed';
        await service.install(AiWorkspaceTool.openClaw);

        // The probe that follows an install would otherwise report a bare
        // "missing" and wipe the only explanation the user ever gets.
        testShell.exitCode = 0;
        testShell.stderrData = '';
        testShell.stdoutData = 'missing';
        await service.refreshStatus(AiWorkspaceTool.openClaw);

        final state = service.getState(AiWorkspaceTool.openClaw);
        expect(state?.status, ToolStatus.error);
        expect(state?.errorMessage, contains('curl failed'));
        // The card still has to stop showing a spinner.
        expect(state?.checked, true);
        expect(state?.hasKnownStatus, true);
      });

      test('a sticky failure still leaves the tool installable, so Retry '
          'works', () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        testShell.exitCode = 1;
        testShell.stderrData = 'curl failed';
        await service.install(AiWorkspaceTool.openClaw);
        testShell.stdoutData = 'missing';
        await service.refreshStatus(AiWorkspaceTool.openClaw);
        expect(service.getState(AiWorkspaceTool.openClaw)?.status,
            ToolStatus.error);

        // Retry is the same install() call the UI's "Retry" button makes.
        testShell.exitCode = 0;
        testShell.stderrData = '';
        testShell.stdoutData = '';
        final retried = await service.install(AiWorkspaceTool.openClaw);

        expect(retried, true);
        final state = service.getState(AiWorkspaceTool.openClaw);
        expect(state?.status, ToolStatus.stopped);
        expect(state?.errorMessage, isNull);
        expect(state?.errorSticky, false);
      });

      test('clearError() releases the tool back to the status probe',
          () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        testShell.exitCode = 1;
        testShell.stderrData = 'curl failed';
        await service.install(AiWorkspaceTool.openClaw);

        service.clearError(AiWorkspaceTool.openClaw);
        expect(service.getState(AiWorkspaceTool.openClaw)?.errorMessage,
            isNull);

        testShell.exitCode = 0;
        testShell.stderrData = '';
        testShell.stdoutData = 'exists';
        await service.refreshStatus(AiWorkspaceTool.openClaw);

        expect(service.getState(AiWorkspaceTool.openClaw)?.status,
            ToolStatus.stopped);
      });

      test('a failed start is sticky too', () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();
        service.getState(AiWorkspaceTool.hermesAgent)?.status =
            ToolStatus.stopped;

        testShell.exitCode = 1;
        testShell.stderrData = 'gateway never bound';
        await service.start(AiWorkspaceTool.hermesAgent);

        testShell.exitCode = 0;
        testShell.stderrData = '';
        testShell.stdoutData = 'missing';
        await service.refreshStatus(AiWorkspaceTool.hermesAgent);

        final state = service.getState(AiWorkspaceTool.hermesAgent);
        expect(state?.status, ToolStatus.error);
        expect(state?.errorMessage, contains('gateway never bound'));
      });

      test('a transient probe failure is not sticky — the next probe still '
          'corrects it', () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        testShell.exitCode = 1;
        testShell.stderrData = 'some transient docker error';
        await service.refreshStatus(AiWorkspaceTool.openWebUi);
        expect(service.getState(AiWorkspaceTool.openWebUi)?.status,
            ToolStatus.error);

        testShell.exitCode = 0;
        testShell.stderrData = '';
        testShell.stdoutData = 'running';
        await service.refreshStatus(AiWorkspaceTool.openWebUi);

        expect(service.getState(AiWorkspaceTool.openWebUi)?.status,
            ToolStatus.running);
      });

      test('installing Open WebUI prepares docker before pulling the image',
          () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        testShell.exitCode = 0;
        final result = await service.install(AiWorkspaceTool.openWebUi);

        expect(result, true);
        // Docker setup command must run before the docker pull/run command.
        final dockerSetupIndex = testShell.allCommands
            .indexWhere((cmd) => cmd.any((a) => a.contains('docker.io')));
        final dockerPullIndex = testShell.allCommands
            .indexWhere((cmd) => cmd.any((a) => a.contains('docker pull')));
        expect(dockerSetupIndex, isNot(-1));
        expect(dockerPullIndex, isNot(-1));
        expect(dockerSetupIndex, lessThan(dockerPullIndex));
      });

      test('does not attempt docker setup for non-docker tools', () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        testShell.exitCode = 0;
        await service.install(AiWorkspaceTool.hermesAgent);

        expect(
          testShell.allCommands.any((cmd) => cmd.any((a) => a.contains('docker.io'))),
          false,
        );
      });

      test('all commands run as root in the dedicated distro', () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        testShell.exitCode = 0;
        await service.install(AiWorkspaceTool.hermesAgent);

        expect(
          testShell.allCommands.where((cmd) => cmd.contains('-d')).every(
                (cmd) => cmd.contains('-u') && cmd.contains('root'),
              ),
          true,
        );
      });

      // Regression: get.hermes-agent.dev and install.openclaw.ai never
      // resolved to anything — they were placeholder URLs. Guard the real,
      // verified install endpoints so a future edit can't silently
      // reintroduce a dead domain.
      test('hermes agent installs from the real nousresearch endpoint',
          () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        testShell.exitCode = 0;
        await service.install(AiWorkspaceTool.hermesAgent);

        expect(
          testShell.lastCommand
              .any((a) => a.contains('hermes-agent.nousresearch.com')),
          true,
        );
        expect(
          testShell.lastCommand.any((a) => a.contains('get.hermes-agent.dev')),
          false,
        );
      });

      test('openclaw installs from the real openclaw.ai endpoint', () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        testShell.exitCode = 0;
        await service.install(AiWorkspaceTool.openClaw);

        expect(
          testShell.lastCommand.any((a) => a.contains('openclaw.ai/install.sh')),
          true,
        );
        expect(
          testShell.lastCommand.any((a) => a.contains('install.openclaw.ai')),
          false,
        );
      });

      // Regression: `curl ... | sh` exits 0 even when curl can't resolve the
      // host (an empty stdin still makes the piped shell "succeed"), which
      // previously made every install of a dead URL report success while
      // installing nothing. `set -o pipefail` makes the pipeline surface
      // curl's own failure instead.
      test('install commands are prefixed with pipefail so a dead curl '
          'target cannot masquerade as success', () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        testShell.exitCode = 0;
        for (final tool in [AiWorkspaceTool.hermesAgent, AiWorkspaceTool.openClaw]) {
          await service.install(tool);
          expect(
            testShell.lastCommand.any((a) => a.contains('set -o pipefail')),
            true,
            reason: '${tool.name} install should be pipefail-guarded',
          );
        }
      });
    });

    group('start/stop', () {
      test('starts a stopped tool', () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        // Pre-set tool as installed/stopped
        final state = service.getState(AiWorkspaceTool.hermesAgent)!;
        state.status = ToolStatus.stopped;

        testShell.exitCode = 0;
        final result = await service.start(AiWorkspaceTool.hermesAgent);

        expect(result, true);
        expect(state.status, ToolStatus.running);
        expect(state.lastStarted, isNotNull);
      });

      test('stops a running tool', () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        final state = service.getState(AiWorkspaceTool.hermesAgent)!;
        state.status = ToolStatus.running;

        testShell.exitCode = 0;
        final result = await service.stop(AiWorkspaceTool.hermesAgent);

        expect(result, true);
        expect(state.status, ToolStatus.stopped);
        expect(state.lastStopped, isNotNull);
      });

      test('cannot start uninstalled tool', () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        // Force tool to notInstalled since init() probes status (mock returns "running")
        final state = service.getState(AiWorkspaceTool.hermesAgent)!;
        state.status = ToolStatus.notInstalled;

        final result = await service.start(AiWorkspaceTool.hermesAgent);

        expect(result, false);
      });

      // `docker start` returning is not the container serving. Without the
      // post-start health probe the card claims "running" for the whole
      // migration window and Open Dashboard walks into a dead port.
      test('a started Open WebUI stays "starting" until it is healthy',
          () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        final state = service.getState(AiWorkspaceTool.openWebUi)!;
        state.status = ToolStatus.stopped;

        testShell.exitCode = 0;
        testShell.stdoutData = 'starting';
        final result = await service.start(AiWorkspaceTool.openWebUi);

        expect(result, true);
        expect(state.status, ToolStatus.starting);
        expect(service.getUrl(AiWorkspaceTool.openWebUi), isNull);
        // Observed on the real app: the card read "Starting up..." while the
        // toast underneath it announced "Open WebUI is running", because the
        // notification was raised before the health re-probe.
        expect(notifications.last,
            'ai-workspace-starting-text'.i18n(['Open WebUI']));
        expect(
          notifications,
          isNot(contains('ai-workspace-started-text'.i18n(['Open WebUI']))),
        );
      });

      // The complement: once the gate says healthy the toast has to go back to
      // announcing the tool as running, or a successful start reads as though
      // it never finished.
      test('a healthy Open WebUI is announced as running', () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        service.getState(AiWorkspaceTool.openWebUi)!.status =
            ToolStatus.stopped;

        testShell.exitCode = 0;
        testShell.stdoutData = 'running';
        await service.start(AiWorkspaceTool.openWebUi);

        expect(notifications.last,
            'ai-workspace-started-text'.i18n(['Open WebUI']));
      });

      // The launcher exits 0 even when the gateway dies immediately, so the
      // start command's own success gate has to be the port. Without it
      // start() flips the card to "running" against a dead port.
      test('starting hermes waits for its port instead of trusting pgrep',
          () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        service.getState(AiWorkspaceTool.hermesAgent)!.status =
            ToolStatus.stopped;
        testShell.stdoutData = '';
        await service.start(AiWorkspaceTool.hermesAgent);

        final command = testShell.lastCommand.last;
        expect(command.contains('setsid hermes gateway'), true);
        expect(command.contains('for _i in'), true);
        expect(command.contains('/dev/tcp/127.0.0.1/9119'), true);
        expect(command.contains('pgrep'), false);
      });

      test('starting openclaw waits for its port', () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        service.getState(AiWorkspaceTool.openClaw)!.status =
            ToolStatus.stopped;
        testShell.stdoutData = '';
        await service.start(AiWorkspaceTool.openClaw);

        final command = testShell.lastCommand.last;
        expect(command.contains('openclaw gateway restart'), true);
        expect(command.contains('for _i in'), true);
        expect(command.contains(r':18789([^0-9]|$)'), true);
        expect(command.contains('"'), false);
      });
    });

    group('uninstall', () {
      test('uninstalls a filesystem-based tool', () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        final state = service.getState(AiWorkspaceTool.hermesAgent)!;
        state.status = ToolStatus.stopped;

        testShell.exitCode = 0;
        final result = await service.uninstall(AiWorkspaceTool.hermesAgent);

        expect(result, true);
        expect(state.status, ToolStatus.notInstalled);
        expect(state.installPath, isNull);
      });

      test('stops running tool before uninstalling', () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        final state = service.getState(AiWorkspaceTool.hermesAgent)!;
        state.status = ToolStatus.running;

        testShell.exitCode = 0; // stop succeeds, then uninstall succeeds
        final result = await service.uninstall(AiWorkspaceTool.hermesAgent);

        expect(result, true);
        expect(state.status, ToolStatus.notInstalled);
      });
    });

    group('refreshStatus', () {
      test('detects running status', () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        // Status check returns "running"
        testShell.stdoutData = 'running';
        await service.refreshStatus(AiWorkspaceTool.hermesAgent);

        expect(
          service.getState(AiWorkspaceTool.hermesAgent)?.status,
          ToolStatus.running,
        );
      });

      test('detects stopped status', () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        // The combined status+existence check's single shell invocation
        // resolves to 'exists' when the process isn't running but the
        // install is still present.
        testShell.stdoutData = 'exists';
        await service.refreshStatus(AiWorkspaceTool.openClaw);

        expect(
          service.getState(AiWorkspaceTool.openClaw)?.status,
          ToolStatus.stopped,
        );
      });

      // Regression: the card read "Not installed" while still printing
      // "Installed: cmd://openclaw" underneath, because only uninstall()
      // ever reset the path.
      test('a notInstalled result clears a stale installPath', () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        testShell.exitCode = 0;
        await service.install(AiWorkspaceTool.openClaw);
        expect(service.getState(AiWorkspaceTool.openClaw)?.installPath,
            'cmd://openclaw');

        // The binary is gone (uninstalled outside the app, distro reset, ...).
        testShell.stdoutData = 'missing';
        await service.refreshStatus(AiWorkspaceTool.openClaw);

        final state = service.getState(AiWorkspaceTool.openClaw);
        expect(state?.status, ToolStatus.notInstalled);
        expect(state?.installPath, isNull);
      });

      test('a confirmed install is re-asserted after a notInstalled probe',
          () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        testShell.stdoutData = 'missing';
        await service.refreshStatus(AiWorkspaceTool.openClaw);
        expect(service.getState(AiWorkspaceTool.openClaw)?.installPath, isNull);

        testShell.stdoutData = 'exists';
        await service.refreshStatus(AiWorkspaceTool.openClaw);

        final state = service.getState(AiWorkspaceTool.openClaw);
        expect(state?.status, ToolStatus.stopped);
        expect(state?.installPath, 'cmd://openclaw');
      });

      test('a cached notInstalled does not resurrect a persisted install path',
          () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        testShell.exitCode = 0;
        await service.install(AiWorkspaceTool.openClaw);
        testShell.stdoutData = 'missing';
        await service.refreshStatus(AiWorkspaceTool.openClaw);

        // Whatever a stale pref still holds, a notInstalled seed must not
        // show a path before the first live probe answers.
        await prefs.setString(
            'AiWorkspaceInstallPath_openClaw', 'cmd://openclaw');
        final restarted = AiWorkspaceService(broker: broker);
        restarted.seedToolStates();

        final state = restarted.getState(AiWorkspaceTool.openClaw);
        expect(state?.status, ToolStatus.notInstalled);
        expect(state?.installPath, isNull);
      });

      test('issues a single wsl call, not two', () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();
        testShell.reset();

        testShell.stdoutData = 'exists';
        await service.refreshStatus(AiWorkspaceTool.openClaw);

        expect(testShell.allCommands.length, 1);
      });

      test('detects a stopped Docker-backed tool via docker inspect',
          () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        testShell.stdoutData = 'exists';
        await service.refreshStatus(AiWorkspaceTool.openWebUi);

        expect(
          service.getState(AiWorkspaceTool.openWebUi)?.status,
          ToolStatus.stopped,
        );
        expect(
          testShell.lastCommand.any((a) => a.contains('docker inspect')),
          true,
        );
      });

      // Regression: dockerd does not auto-start on distro boot, so right
      // after a cold WSL start the daemon is down and `docker inspect`/
      // `docker ps` fail — which used to get misread as "not installed"
      // even for a genuinely-installed tool, and then made the next
      // install attempt fail with "name already in use".
      test('starts the docker daemon before checking a docker-backed tool',
          () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        testShell.stdoutData = 'exists';
        await service.refreshStatus(AiWorkspaceTool.openWebUi);

        expect(
          testShell.lastCommand.any((a) => a.contains('service docker start')),
          true,
        );
      });

      test('does not try to start docker for non-docker tools', () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        testShell.stdoutData = 'exists';
        await service.refreshStatus(AiWorkspaceTool.hermesAgent);

        expect(
          testShell.lastCommand.any((a) => a.contains('service docker start')),
          false,
        );
      });

      // Open WebUI's container reports `Up` for the ~2 minutes its alembic
      // migrations take, during which nothing answers on the port and a
      // restart kills it. Docker's healthcheck is the only source that knows
      // the difference, so the probe has to consult it.
      test('reports Open WebUI as starting while its container is migrating',
          () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        testShell.stdoutData = 'starting';
        await service.refreshStatus(AiWorkspaceTool.openWebUi);

        final state = service.getState(AiWorkspaceTool.openWebUi);
        expect(state?.status, ToolStatus.starting);
        expect(state?.installPath, 'docker://open-webui');
      });

      test('reports Open WebUI as running once its container is healthy',
          () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        testShell.stdoutData = 'running';
        await service.refreshStatus(AiWorkspaceTool.openWebUi);

        expect(
          service.getState(AiWorkspaceTool.openWebUi)?.status,
          ToolStatus.running,
        );
      });

      test('gates the Open WebUI probe on docker inspect health', () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        testShell.stdoutData = 'running';
        await service.refreshStatus(AiWorkspaceTool.openWebUi);

        final command = testShell.lastCommand.last;
        expect(command.contains('{{.State.Health.Status}}'), true);
        // `runInShell: false` means a `"` reaches bash literally and breaks
        // the --format filter; the Go template has to be single-quoted.
        expect(command.contains('"'), false);
      });

      test('does not health-gate tools without a healthcheck', () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        testShell.stdoutData = 'running';
        await service.refreshStatus(AiWorkspaceTool.hermesAgent);

        expect(
          testShell.lastCommand.last.contains('{{.State.Health.Status}}'),
          false,
        );
        expect(
          service.getState(AiWorkspaceTool.hermesAgent)?.status,
          ToolStatus.running,
        );
      });

      // An unhealthy container is still an installed one: the health gate
      // answers `stopped`, which must not fall through to notInstalled and
      // wipe the install path with it.
      test('an unhealthy container reads as stopped, not notInstalled',
          () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        testShell.stdoutData = 'stopped';
        await service.refreshStatus(AiWorkspaceTool.openWebUi);

        final state = service.getState(AiWorkspaceTool.openWebUi);
        expect(state?.status, ToolStatus.stopped);
        expect(state?.installPath, 'docker://open-webui');
      });

      // Regression: the exists-check used to be `[ -d "~/.hermes-agent" ]`,
      // which never matches — `~` doesn't expand inside double quotes in
      // bash, so a genuinely-installed tool with no process currently
      // running was always misreported as not installed. `command -v`
      // checks PATH instead and has no such quoting pitfall.
      test('checks hermes agent installation via command -v, not a path',
          () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        testShell.stdoutData = 'exists';
        await service.refreshStatus(AiWorkspaceTool.hermesAgent);

        expect(
          testShell.lastCommand.any((a) => a.contains('command -v hermes')),
          true,
        );
        expect(
          testShell.lastCommand.any((a) => a.contains('~/.hermes')),
          false,
        );
      });

      test('checks openclaw installation via command -v, not a path',
          () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        testShell.stdoutData = 'exists';
        await service.refreshStatus(AiWorkspaceTool.openClaw);

        expect(
          testShell.lastCommand.any((a) => a.contains('command -v openclaw')),
          true,
        );
      });

      // Both gateways used to be probed with `pgrep`, which proves only that
      // a process exists: OpenClaw's gateway stays alive after a failed bind
      // and Hermes' launcher exits 0 while its gateway is already dead, so a
      // card read "running" against a port that refused every connection.
      test('hermes agent status is decided by its port, not by pgrep',
          () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        testShell.stdoutData = 'exists';
        await service.refreshStatus(AiWorkspaceTool.hermesAgent);

        final command = testShell.lastCommand.last;
        expect(command.contains('9119'), true);
        expect(command.contains('/dev/tcp/127.0.0.1/9119'), true);
        expect(command.contains('pgrep'), false);
      });

      test('openclaw status is decided by its port, not by pgrep', () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        testShell.stdoutData = 'exists';
        await service.refreshStatus(AiWorkspaceTool.openClaw);

        final command = testShell.lastCommand.last;
        expect(command.contains('18789'), true);
        expect(command.contains('/dev/tcp/127.0.0.1/18789'), true);
        expect(command.contains('pgrep'), false);
      });

      // A bare `grep -q 18789` also matches `:187890` and any other column
      // carrying those digits, so the port has to be anchored.
      test('the port probe anchors the port number', () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        testShell.stdoutData = 'exists';
        await service.refreshStatus(AiWorkspaceTool.openClaw);

        expect(
          testShell.lastCommand.last.contains(r':18789([^0-9]|$)'),
          true,
        );
        // `runInShell: false` means a `"` reaches bash literally.
        expect(testShell.lastCommand.last.contains('"'), false);
      });

      // The port probe answering "not listening" must not be read as "not
      // installed": the probe falls through to the exists check, and an
      // installed-but-dead gateway keeps its card and its install path.
      test('a gateway that is not listening reads as stopped, keeping its '
          'install path', () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        testShell.stdoutData = 'exists';
        await service.refreshStatus(AiWorkspaceTool.hermesAgent);

        final state = service.getState(AiWorkspaceTool.hermesAgent);
        expect(state?.status, ToolStatus.stopped);
        expect(state?.installPath, 'cmd://hermes');
        // The else-branch of the port probe is what produced that answer.
        expect(
          testShell.lastCommand.last.contains('command -v hermes'),
          true,
        );
      });

      test('handles error gracefully', () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        // Status check fails with stderr about distro not found
        testShell.exitCode = 1;
        testShell.stderrData = 'distribution ai-workspace could not be found';
        await service.refreshStatus(AiWorkspaceTool.openWebUi);

        expect(
          service.getState(AiWorkspaceTool.openWebUi)?.status,
          ToolStatus.notInstalled,
        );
      });

      // Regression coverage for `checked`: a UI decides whether to show a
      // checking spinner based on whether a tool was *attempted*, not
      // whether that attempt succeeded — so `checked` must end up true on
      // every path through refreshStatus, including the error ones.
      test('marks the tool as checked even when the distro is missing',
          () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        testShell.exitCode = 1;
        testShell.stderrData = 'distribution ai-workspace could not be found';
        await service.refreshStatus(AiWorkspaceTool.openWebUi);

        expect(service.getState(AiWorkspaceTool.openWebUi)?.checked, true);
      });

      test('marks the tool as checked even when the broker throws',
          () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        testShell.throwOnRun = true;
        await service.refreshStatus(AiWorkspaceTool.openWebUi);

        expect(service.getState(AiWorkspaceTool.openWebUi)?.checked, true);
      });

      test('a freshly-seeded tool is not checked yet', () {
        service.seedToolStates();

        for (final tool in AiWorkspaceTool.values) {
          expect(service.getState(tool)?.checked, false);
        }
      });
    });

    group('getUrl', () {
      test('returns URL for running tool', () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        final state = service.getState(AiWorkspaceTool.hermesAgent)!;
        state.status = ToolStatus.running;

        expect(
          service.getUrl(AiWorkspaceTool.hermesAgent),
          'http://localhost:9119',
        );
      });

      test('returns null for non-running tool', () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        final state = service.getState(AiWorkspaceTool.openClaw)!;
        state.status = ToolStatus.stopped;

        expect(service.getUrl(AiWorkspaceTool.openClaw), isNull);
      });
    });

    group('getDashboardUrl', () {
      // The whole point of the starting state: the dashboard must stay shut
      // until the container is actually serving.
      test('returns null while the tool is still starting up', () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        final state = service.getState(AiWorkspaceTool.openWebUi)!;
        state.status = ToolStatus.starting;

        expect(await service.getDashboardUrl(AiWorkspaceTool.openWebUi),
            isNull);
      });

      test('returns null for a tool that is not running', () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        final state = service.getState(AiWorkspaceTool.openWebUi)!;
        state.status = ToolStatus.stopped;

        expect(await service.getDashboardUrl(AiWorkspaceTool.openWebUi), isNull);
      });

      test('Open WebUI uses the static port without any extra WSL call',
          () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        final state = service.getState(AiWorkspaceTool.openWebUi)!;
        state.status = ToolStatus.running;
        testShell.allCommands.clear();

        final url = await service.getDashboardUrl(AiWorkspaceTool.openWebUi);

        expect(url, 'http://localhost:8083');
        expect(testShell.allCommands, isEmpty);
      });

      test('hermes agent runs "hermes dashboard" and returns the printed URL',
          () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        final state = service.getState(AiWorkspaceTool.hermesAgent)!;
        state.status = ToolStatus.running;
        testShell.stdoutData = 'http://127.0.0.1:9119/?token=abc123';

        final url = await service.getDashboardUrl(AiWorkspaceTool.hermesAgent);

        expect(url, 'http://127.0.0.1:9119/?token=abc123');
        expect(
          testShell.lastCommand.any((a) => a.contains('hermes dashboard')),
          true,
        );
      });

      test('openclaw runs "openclaw dashboard" and returns the printed URL',
          () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        final state = service.getState(AiWorkspaceTool.openClaw)!;
        state.status = ToolStatus.running;
        testShell.stdoutData = 'http://127.0.0.1:18789/pair/xyz';

        final url = await service.getDashboardUrl(AiWorkspaceTool.openClaw);

        expect(url, 'http://127.0.0.1:18789/pair/xyz');
        expect(
          testShell.lastCommand.any((a) => a.contains('openclaw dashboard')),
          true,
        );
      });

      test('returns null when no URL is found in the command output',
          () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        final state = service.getState(AiWorkspaceTool.hermesAgent)!;
        state.status = ToolStatus.running;
        testShell.stdoutData = '';
        testShell.exitCode = 1;

        expect(await service.getDashboardUrl(AiWorkspaceTool.hermesAgent), isNull);
      });

      // Regression: docker reporting a container "Up" (or a gateway CLI
      // printing a link) doesn't guarantee the web server inside has
      // actually finished starting — clicking "Open Dashboard" used to
      // open a browser tab to a URL nothing was listening on yet, which
      // showed as an empty response. getDashboardUrl now waits for
      // something to actually answer before returning a URL at all.
      test('does not return a URL that never becomes reachable', () async {
        final unreachable = AiWorkspaceService(
          broker: broker,
          reachabilityChecker: (_) async => false,
        );
        testShell.stdoutData = 'ai-workspace';
        await unreachable.init();

        final state = unreachable.getState(AiWorkspaceTool.openWebUi)!;
        state.status = ToolStatus.running;

        expect(
          await unreachable.getDashboardUrl(AiWorkspaceTool.openWebUi),
          isNull,
        );
      });

      test('returns the URL once the reachability check reports it is live',
          () async {
        var callCount = 0;
        final flakyThenUp = AiWorkspaceService(
          broker: broker,
          // Simulates the container being "Up" per docker but not actually
          // serving yet for the first couple of polls.
          reachabilityChecker: (_) async => (++callCount) >= 3,
        );
        testShell.stdoutData = 'ai-workspace';
        await flakyThenUp.init();

        final state = flakyThenUp.getState(AiWorkspaceTool.openWebUi)!;
        state.status = ToolStatus.running;

        final url = await flakyThenUp.getDashboardUrl(AiWorkspaceTool.openWebUi);

        expect(url, 'http://localhost:8083');
        expect(callCount, greaterThanOrEqualTo(3));
      });
    });

    group('wsl command routing', () {
      // Without --exec, wsl.exe re-joins argv and runs it through the
      // distro's default shell, which eats a level of quoting: the script
      // handed to `bash -c` is split, only its first word reaches the child
      // bash, and the remainder executes in the outer shell. That is why the
      // probe's `_s=$(...)` was always empty and the health gate could never
      // be reached. Measured live 2026-08-28.
      test('shell commands are passed through --exec so argv survives',
          () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        testShell.stdoutData = 'exists';
        await service.refreshStatus(AiWorkspaceTool.openWebUi);

        final command = testShell.lastCommand;
        expect(command.contains('--exec'), true);
        expect(
          command.indexOf('--exec'),
          lessThan(command.indexOf('bash')),
          reason: '--exec must precede the command it protects',
        );
      });

      test('all commands use wsl with -d ai-workspace flag', () async {
        // Distro check + init
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        // Install command should route through WSL
        await service.install(AiWorkspaceTool.hermesAgent);

        expect(testShell.lastCommand[0], 'wsl');
        expect(
          testShell.allCommands.any(
            (cmd) => cmd.contains('-d') && cmd.contains(kAiWorkspaceDistro),
          ),
          true,
        );
      });
    });

    // Every test above stubs the probe's *answer* and asserts how the service
    // reads it. These run the exact bash program the service sends into the
    // distro and assert the program itself produces the right answer, with
    // shell functions standing in for `ss`, `docker` and the tool binaries.
    group('probe script semantics', () {
      /// The bash program `refreshStatus` sends for [tool].
      Future<String> probeScriptFor(AiWorkspaceTool tool) async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();
        testShell.stdoutData = 'exists';
        await service.refreshStatus(tool);
        return testShell.lastCommand.last;
      }

      /// Fast-forwards the daemon wait loop; nothing here needs real seconds.
      const noSleep = 'sleep() { :; }; ';

      /// A `docker` stub. [health] is the body of the `inspect` branch, [ps]
      /// what `docker ps` prints.
      String dockerStub({
        required String health,
        String ps = 'abcd open-webui Up 2 minutes',
      }) =>
          '$noSleep'
          'docker() { case \$1 in '
          'info) return 0;; '
          "ps) echo '$ps';; "
          'inspect) $health;; '
          'esac; }; ';

      test('a gateway whose port is listening reads as running', () async {
        final script = await probeScriptFor(AiWorkspaceTool.openClaw);

        final answer = await _runProbeScript(
          "ss() { echo 'LISTEN 0 4096 127.0.0.1:18789 0.0.0.0:*'; }; ",
          script,
        );

        expect(answer, 'running');
      });

      test('the hermes probe answers on its own port', () async {
        final script = await probeScriptFor(AiWorkspaceTool.hermesAgent);

        final answer = await _runProbeScript(
          "ss() { echo 'LISTEN 0 4096 127.0.0.1:9119 0.0.0.0:*'; }; ",
          script,
        );

        expect(answer, 'running');
      });

      // The bullet this phase set out to prove: `pgrep` finds the gateway and
      // would have reported it running, while nothing answers on the port.
      // The probe has to say "installed, not serving" instead — which
      // refreshStatus maps to stopped, keeping the card and its install path.
      test('a gateway process that exists while nothing listens reads as '
          'installed, not running', () async {
        if (await _hostPortIsOpen(18789)) {
          markTestSkipped('a real service holds 18789 on this machine, so the '
              '/dev/tcp fallback cannot be exercised');
          return;
        }
        final script = await probeScriptFor(AiWorkspaceTool.openClaw);

        final answer = await _runProbeScript(
          "ss() { echo 'LISTEN 0 4096 127.0.0.1:22 0.0.0.0:*'; }; "
          'pgrep() { echo 4242; }; openclaw() { :; }; ',
          script,
        );

        expect(answer, 'exists');
      });

      test('a gateway that is neither listening nor installed reads as '
          'missing', () async {
        if (await _hostPortIsOpen(18789)) {
          markTestSkipped('a real service holds 18789 on this machine');
          return;
        }
        final script = await probeScriptFor(AiWorkspaceTool.openClaw);

        final answer = await _runProbeScript('ss() { :; }; ', script);

        expect(answer, 'missing');
      });

      // Regression: a bare `grep -q 18789` matches `:187890` and any other
      // column carrying those digits, so an unrelated socket reported the
      // gateway as running.
      test('a neighbouring port is not mistaken for the gateway port',
          () async {
        if (await _hostPortIsOpen(18789)) {
          markTestSkipped('a real service holds 18789 on this machine');
          return;
        }
        final script = await probeScriptFor(AiWorkspaceTool.openClaw);

        final answer = await _runProbeScript(
          "ss() { echo 'LISTEN 0 4096 127.0.0.1:187890 0.0.0.0:*'; }; "
          'openclaw() { :; }; ',
          script,
        );

        expect(answer, 'exists');
      });

      // Open WebUI runs ~2 minutes of alembic migrations while its container
      // already reports `Up`, and probing or restarting it inside that window
      // kills it. `docker ps` alone cannot tell the difference.
      test('a migrating Open WebUI container reads as starting, not running',
          () async {
        final script = await probeScriptFor(AiWorkspaceTool.openWebUi);

        final answer = await _runProbeScript(
          dockerStub(health: 'echo starting'),
          script,
        );

        expect(answer, 'starting');
      });

      test('a healthy Open WebUI container reads as running', () async {
        final script = await probeScriptFor(AiWorkspaceTool.openWebUi);

        final answer = await _runProbeScript(
          dockerStub(health: 'echo healthy'),
          script,
        );

        expect(answer, 'running');
      });

      test('an unhealthy Open WebUI container reads as stopped', () async {
        final script = await probeScriptFor(AiWorkspaceTool.openWebUi);

        final answer = await _runProbeScript(
          dockerStub(health: 'echo unhealthy'),
          script,
        );

        expect(answer, 'stopped');
      });

      // An image with no HEALTHCHECK makes `docker inspect` fail and leaves
      // the variable empty. An empty answer is no evidence of a problem, so
      // the gate must fall through to running rather than strand the card.
      test('an Open WebUI image with no healthcheck still reads as running',
          () async {
        final script = await probeScriptFor(AiWorkspaceTool.openWebUi);

        final answer = await _runProbeScript(
          dockerStub(health: 'return 1'),
          script,
        );

        expect(answer, 'running');
      });

      test('a container that is not up falls through to the existence check',
          () async {
        final script = await probeScriptFor(AiWorkspaceTool.openWebUi);

        final answer = await _runProbeScript(
          dockerStub(health: 'echo healthy', ps: ''),
          script,
        );

        expect(answer, 'exists');
      });

      // A daemon that never answers says nothing about whether the tool is
      // installed, so the probe reports that instead of guessing.
      test('a docker daemon that never comes up prints the dockerdown marker',
          () async {
        final script = await probeScriptFor(AiWorkspaceTool.openWebUi);

        final answer = await _runProbeScript(
          '${noSleep}docker() { return 1; }; ',
          script,
        );

        expect(answer, 'dockerdown');
      });
    }, skip: _bash == null ? 'no bash available to run the probe scripts' : null);
  });
}
