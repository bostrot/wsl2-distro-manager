// Install/start/status lifecycle for the AI Workspace tools. Every command
// runs inside the dedicated [kAiWorkspaceDistro] Ubuntu distro.

import 'dart:async';
import 'dart:io' show Process;

import 'package:dio/dio.dart';
import 'package:localization/localization.dart';

import '../../components/helpers.dart';
import '../../components/notify.dart';
import '../execution/broker.dart';
import '../execution/models.dart';

/// The dedicated WSL distro name used for AI workspace tools.
const String kAiWorkspaceDistro = 'ai-workspace';

/// Printed by the status probe when dockerd never became reachable. Distinct
/// from "missing" so an unavailable daemon is never mistaken for an
/// uninstalled tool.
const String _kDockerDownMarker = 'dockerdown';

/// Blocks until dockerd answers, up to ~20s. `service docker start` returns as
/// soon as the init script forks, well before the socket exists, so anything
/// that talks to Docker has to wait for this first.
/// No `$(seq ...)` and no subshell parentheses: both got mangled on the way
/// through the Windows command line into `wsl.exe`, surfacing as
/// `bash: -c: line 2: syntax error near unexpected token '2'`. Root cause
/// found 2026-08-28 — `wsl.exe` re-ran the flattened command through the
/// distro's default shell; see the `--exec` note on [_wslArgs]. The explicit
/// list is kept because it costs nothing and works under either form.
const String _kDockerWaitLoop =
    'for _i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do '
    'docker info >/dev/null 2>&1 && break; sleep 1; done; ';

/// Supported AI workspace tools.
enum AiWorkspaceTool { hermesAgent, openClaw, openWebUi }

/// Status of a workspace tool instance.
///
/// [starting] is deliberately distinct from [running]: Open WebUI's container
/// reports `Up` about two minutes before it can answer, while alembic
/// migrations run — and probing or restarting it inside that window kills it
/// (measured 2026-08-27). Reporting it as [running] invites exactly that.
enum ToolStatus { notInstalled, stopped, starting, running, error }

/// Configuration for an AI workspace tool.
class ToolConfig {
  final String name;
  final String installCommand;
  final String startCommand;
  final String stopCommand;
  final String statusCheck;
  final int port;
  final String defaultInstallPath;

  /// Command that starts the tool's dashboard and prints its URL. Null when
  /// [port] alone is enough.
  final String? dashboardCommand;

  /// Second-stage probe, run only once [statusCheck] has said the tool is up.
  /// Must echo exactly one of `running`, `starting` or `stopped`. Null means
  /// "[statusCheck] is the whole answer" and up counts as running.
  ///
  /// This exists because a container being up is not the same as it serving:
  /// see [ToolStatus.starting].
  final String? healthCheck;

  const ToolConfig({
    required this.name,
    required this.installCommand,
    required this.startCommand,
    required this.stopCommand,
    required this.statusCheck,
    required this.port,
    required this.defaultInstallPath,
    this.dashboardCommand,
    this.healthCheck,
  });
}

/// Commands assume an Ubuntu environment (curl, bash, docker available).
const Map<AiWorkspaceTool, ToolConfig> _toolConfigs = {
  AiWorkspaceTool.hermesAgent: ToolConfig(
    name: 'Hermes Agent',
    installCommand: 'curl -fsSL https://hermes-agent.nousresearch.com/install.sh '
        '| bash -s -- --non-interactive',
    // setsid, not `nohup &`: the launcher survives this one-shot wsl call.
    // The trailing pgrep is the real success check — the launcher exits 0
    // even if the gateway dies immediately.
    startCommand: 'pkill -f \'[h]ermes.*gateway\' >/dev/null 2>&1; '
        'mkdir -p \$HOME/.hermes; '
        'setsid hermes gateway </dev/null >>\$HOME/.hermes/gateway.log 2>&1 & '
        'disown; sleep 1; pgrep -f \'[h]ermes.*gateway\' >/dev/null',
    stopCommand: 'pkill -f \'[h]ermes.*gateway\' || true',
    statusCheck:
        'pgrep -f \'[h]ermes.*gateway\' > /dev/null && echo running || echo stopped',
    port: 9119,
    defaultInstallPath: 'cmd://hermes',
    dashboardCommand: 'hermes dashboard',
  ),
  AiWorkspaceTool.openClaw: ToolConfig(
    name: 'OpenClaw',
    installCommand:
        'curl -fsSL https://openclaw.ai/install.sh | bash -s -- --no-onboard --no-prompt',
    // `gateway install --force` first leaves the service unable to bind, so
    // restart on its own is tried first and the reinstall is only a fallback.
    // The wait is on the port, not the process: the gateway takes several
    // seconds to listen and exists long before it serves.
    // `gateway install --force` first leaves the service unable to bind, so
    // plain restart is what runs. The wait is on the port, not the process:
    // the gateway exists for seconds before it ever listens.
    startCommand: 'openclaw gateway restart >/dev/null 2>&1; '
        'for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do '
        'sleep 1; ss -ltn 2>/dev/null | grep -q 18789 && break; done; '
        'ss -ltn 2>/dev/null | grep -q 18789',
    stopCommand: 'openclaw gateway stop >/dev/null 2>&1; '
        'pkill -f \'[o]penclaw\' || true',
    // A live process proves nothing — it routinely runs without ever binding.
    statusCheck:
        'ss -ltn 2>/dev/null | grep -q 18789 && echo running || echo stopped',
    port: 18789,
    defaultInstallPath: 'cmd://openclaw',
    dashboardCommand: 'openclaw dashboard',
  ),
  AiWorkspaceTool.openWebUi: ToolConfig(
    name: 'Open WebUI',
    // `docker rm -f` keeps this idempotent — a re-install must not fail with
    // "name already in use".
    installCommand:
        'docker pull ghcr.io/open-webui/open-webui:latest && docker rm -f open-webui >/dev/null 2>&1; docker run -d -p 8083:8080 --name open-webui ghcr.io/open-webui/open-webui:latest',
    startCommand:
        'docker start open-webui || (docker pull ghcr.io/open-webui/open-webui:latest && docker run -d -p 8083:8080 --name open-webui ghcr.io/open-webui/open-webui:latest)',
    stopCommand: 'docker stop open-webui || true',
    statusCheck:
        'docker ps --filter name=open-webui | grep -q Up && echo running || echo stopped',
    // `Up` is not `serving`: the container runs its alembic migrations for
    // ~2 minutes before the web server answers, and touching it in that
    // window kills it. Docker's own healthcheck is the only thing that knows
    // the difference.
    // Single quotes around the Go template, never double: `runInShell: false`
    // means a `"` reaches bash literally and breaks the filter. `x$_h` rather
    // than a quoted comparison for the same reason — an image with no
    // HEALTHCHECK makes `docker inspect` fail and leaves `_h` empty, and an
    // empty answer is no evidence of a problem, so it falls through to
    // running.
    healthCheck:
        '_h=\$(docker inspect --format \'{{.State.Health.Status}}\' open-webui 2>/dev/null); '
        'if [ x\$_h = xstarting ]; then echo starting; '
        'elif [ x\$_h = xunhealthy ]; then echo stopped; '
        'else echo running; fi',
    port: 8083,
    defaultInstallPath: 'docker://open-webui',
  ),
};

/// State tracker for a single tool instance.
class ToolState {
  final AiWorkspaceTool tool;

  ToolStatus _status;

  ToolStatus get status => _status;

  /// The single reset point for [installPath]: a tool that is not installed
  /// cannot have one. Routing every assignment through this setter is what
  /// stops a card from reading "Not installed" while still showing
  /// `Installed: cmd://openclaw` underneath — the probe that downgrades a
  /// tool to [ToolStatus.notInstalled] used to leave the path from the last
  /// successful install behind. Callers set [installPath] *after* the status.
  set status(ToolStatus value) {
    _status = value;
    if (value == ToolStatus.notInstalled) {
      installPath = null;
    }
  }

  String? installPath;
  int port;
  DateTime? lastStarted;
  DateTime? lastStopped;
  String? errorMessage;
  /// A live WSL check completed this session — decides whether a background
  /// refresh is still owed.
  bool checked;

  /// [status] holds real information (live or cached) rather than the blank
  /// default — decides spinner vs. badge in the UI.
  bool hasKnownStatus;

  /// [status] and [errorMessage] describe a failed *user action* and belong to
  /// the user until they act again. [AiWorkspaceService.refreshStatus] leaves
  /// a sticky failure alone; without this the probe that follows a failed
  /// install replaces the reason with a bare "Not installed" before anyone
  /// can read it. Cleared by [AiWorkspaceService.clearError].
  bool errorSticky;

  ToolState({
    required this.tool,
    ToolStatus status = ToolStatus.notInstalled,
    this.installPath,
    required this.port,
    this.lastStarted,
    this.lastStopped,
    this.errorMessage,
    this.checked = false,
    this.hasKnownStatus = false,
    this.errorSticky = false,
  }) : _status = status {
    // The setter's invariant has to hold for a freshly built state too: a
    // persisted install path must not outlive a cached notInstalled.
    if (_status == ToolStatus.notInstalled) {
      installPath = null;
    }
  }
}

/// Checks whether [url] is actually serving requests yet. Injectable so
/// tests don't need a real HTTP stack.
typedef DashboardReachabilityChecker = Future<bool> Function(String url);

Future<bool> _defaultReachabilityCheck(String url) async {
  final dio = Dio();
  try {
    final response = await dio.get<void>(
      url,
      options: Options(
        sendTimeout: const Duration(seconds: 3),
        receiveTimeout: const Duration(seconds: 3),
        // Any response counts, 4xx/5xx included — we only care that
        // something is listening.
        validateStatus: (_) => true,
      ),
    );
    return response.statusCode != null;
  } catch (_) {
    return false;
  } finally {
    dio.close();
  }
}

/// Service for managing AI workspace tools.
class AiWorkspaceService {
  final ExecutionBroker _broker;
  final Map<AiWorkspaceTool, ToolState> _toolStates = {};
  final DashboardReachabilityChecker _isReachable;
  bool _distroReady = false;
  bool _dockerReady = false;

  // Installs outlive the screen that started them. Tracking them here — not
  // in the page's State — is what lets the UI show progress again after the
  // user navigates away and back, and stops a status refresh from
  // overwriting an install that is still running.
  final Set<AiWorkspaceTool> _installing = {};

  // WSL shuts a distro down once its last session exits, which takes systemd
  // user services with it — measured: a started gateway is listening while a
  // session is held open and gone ~20s after the last one closes. Every action
  // here is its own one-shot `wsl` call, so without this the gateway is
  // already dead by the time "open dashboard" runs.
  Process? _keepAlive;

  AiWorkspaceService({
    required ExecutionBroker broker,
    DashboardReachabilityChecker? reachabilityChecker,
  })  : _broker = broker,
        _isReachable = reachabilityChecker ?? _defaultReachabilityCheck;

  Map<AiWorkspaceTool, ToolState> get toolStates =>
      Map.unmodifiable(_toolStates);

  ToolState? getState(AiWorkspaceTool tool) => _toolStates[tool];

  /// True while [install] is still running for [tool], including across a
  /// navigation away from the AI Workspace page.
  bool isInstalling(AiWorkspaceTool tool) => _installing.contains(tool);

  /// Holds one WSL session open so long-running tools survive between the
  /// one-shot calls that start, probe and use them. Safe to call repeatedly.
  Future<void> ensureKeepAlive() async {
    if (_keepAlive != null) return;
    try {
      _keepAlive = await _broker.startPersistent(ExecutionRequest(
        command: 'wsl',
        arguments: ['-d', kAiWorkspaceDistro, '-u', 'root', 'sleep', 'infinity'],
      ));
      // If WSL drops the session, forget the handle so the next call retries.
      unawaited(_keepAlive!.exitCode.then((_) => _keepAlive = null));
    } catch (_) {
      // A keep-alive is an optimisation, never a reason to fail the action.
      _keepAlive = null;
    }
  }

  /// Releases the held session. The distro is then free to shut down.
  void dispose() {
    _keepAlive?.kill();
    _keepAlive = null;
  }

  // -----------------------------------------------------------------------
  // Distro management
  // -----------------------------------------------------------------------

  /// Creates the distro if missing. With [forUninstall] it must already
  /// exist and the call fails instead.
  Future<void> ensureDistro({bool forUninstall = false}) async {
    if (_distroReady) return;

    if (await _distroExists()) {
      _distroReady = true;
      return;
    }

    if (forUninstall) {
      throw Exception(
          'AI workspace distro is not installed. Cannot uninstall.');
    }

    await _createUbuntuDistro();
  }

  /// Whether WSL has [kAiWorkspaceDistro] registered.
  Future<bool> _distroExists() async {
    final listResult = await _broker.run(ExecutionRequest(
      command: 'wsl',
      arguments: ['--list', '--quiet'],
      timeout: const Duration(seconds: 10),
    ));
    if (!listResult.isSuccess) return false;
    return listResult.stdout
        .split('\n')
        .map((s) => s.trim())
        .contains(kAiWorkspaceDistro);
  }

  /// Deliberately separate from any pre-existing "Ubuntu" distro: tools
  /// installed there are not visible here.
  Future<void> _createUbuntuDistro() async {
    Notify.message('ai-workspace-preparing-text'.i18n(), loading: true);
    final installResult = await _broker.run(ExecutionRequest(
      command: 'wsl',
      arguments: ['--install', 'Ubuntu', '--name', kAiWorkspaceDistro],
      timeout: const Duration(minutes: 10),
    ));

    if (installResult.isSuccess) {
      _distroReady = true;
      return;
    }

    // `wsl --install` exits non-zero even when it created the distro — it
    // also tries to run the interactive first-boot setup, which has no
    // console here. The registration is what matters, so ask WSL rather than
    // trusting the exit code.
    if (await _distroExists()) {
      _distroReady = true;
      return;
    }

    // stderr is often empty on this path; fall back to stdout so the message
    // is not just a bare colon.
    final detail = [installResult.stderr, installResult.stdout]
        .map((s) => s.trim())
        .firstWhere((s) => s.isNotEmpty, orElse: () => 'no output from wsl');
    throw Exception('Failed to create the AI workspace distro: $detail');
  }

  /// Runs as root — this distro is automation-only.
  ///
  /// `--exec` is load-bearing, not decoration. Without it `wsl.exe` re-joins
  /// the argv it was given into one string and hands that to the distro's
  /// default shell, which strips a level of quoting: `bash -c '<script>'`
  /// arrives as `bash -c <first word of script>` followed by the rest of the
  /// script running in the *outer* shell. Measured against a live distro on
  /// 2026-08-28 — `bash -c 'X=hello; echo [$X]'` prints `[]`, because the
  /// assignment happened in a throwaway child, and `$BASH_EXECUTION_STRING`
  /// comes back as `bash -c echo …` rather than the script itself. That is
  /// what made the status probe's `_s=$(…)` permanently empty (so the
  /// `running` branch could never be taken) and what silently defeated
  /// `set -o pipefail` on installs. `--exec` skips the default shell and
  /// passes argv through intact.
  List<String> _wslArgs(String shellCommand) {
    return [
      '-d',
      kAiWorkspaceDistro,
      '-u',
      'root',
      '--exec',
      'bash',
      '-c',
      shellCommand,
    ];
  }

  /// Installs docker.io on first use — the base Ubuntu image has no Docker.
  Future<void> _ensureDockerReady() async {
    if (_dockerReady) return;

    Notify.message('ai-workspace-docker-setup-text'.i18n(), loading: true);
    // The daemon wait matters as much as the install: `service docker start`
    // returns before dockerd has a socket, and the `docker pull` that follows
    // this call would hit a daemon that is not up yet.
    const setupCommand = 'command -v docker >/dev/null 2>&1 || '
        '(apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker.io); '
        'service docker status >/dev/null 2>&1 || service docker start; '
        '$_kDockerWaitLoop'
        'docker info >/dev/null 2>&1';

    final result = await _broker.run(ExecutionRequest(
      command: 'wsl',
      arguments: _wslArgs(setupCommand),
      timeout: const Duration(minutes: 5),
    ));

    if (!result.isSuccess) {
      throw Exception(
          'Failed to prepare Docker in the AI workspace distro: ${result.stderr}');
    }
    _dockerReady = true;
  }

  /// Matches on the untranslated WSL error code — wsl.exe localizes its
  /// error text.
  static bool _indicatesMissingDistro(String stderr) {
    final lower = stderr.toLowerCase();
    return lower.contains('wsl_e_distro_not_found') ||
        lower.contains('not found') ||
        lower.contains(kAiWorkspaceDistro.toLowerCase());
  }

  // Last *confirmed* status per tool, persisted so the UI can show a real
  // answer at startup instead of a spinner. Written only from confirmed
  // results, never from a transient failure. Still just a cache —
  // [ensureInitialized] always re-verifies in the background.

  static String _statusPrefsKey(AiWorkspaceTool tool) =>
      'AiWorkspaceStatus_${tool.name}';
  static String _installPathPrefsKey(AiWorkspaceTool tool) =>
      'AiWorkspaceInstallPath_${tool.name}';

  void _persistConfirmedState(AiWorkspaceTool tool) {
    final state = _toolStates[tool];
    if (state == null) return;
    prefs.setString(_statusPrefsKey(tool), state.status.name);
    final installPath = state.installPath;
    if (installPath != null) {
      prefs.setString(_installPathPrefsKey(tool), installPath);
    } else {
      prefs.remove(_installPathPrefsKey(tool));
    }
  }

  ToolStatus? _loadCachedStatus(AiWorkspaceTool tool) {
    final raw = prefs.getString(_statusPrefsKey(tool));
    if (raw == null) return null;
    for (final status in ToolStatus.values) {
      if (status.name == raw) return status;
    }
    return null;
  }

  /// Creates tool state entries, seeded from the persisted cache.
  /// Synchronous — no WSL calls.
  void seedToolStates() {
    for (final tool in AiWorkspaceTool.values) {
      final config = _toolConfigs[tool]!;
      final cachedStatus = _loadCachedStatus(tool);
      _toolStates[tool] = ToolState(
        tool: tool,
        port: config.port,
        status: cachedStatus ?? ToolStatus.notInstalled,
        // A cached notInstalled drops the path in the constructor, so the
        // no-cache case needs no branch of its own.
        installPath: prefs.getString(_installPathPrefsKey(tool)),
        hasKnownStatus: cachedStatus != null,
      );
    }
  }

  /// Blocks until every tool has been probed. UI layers that want to render
  /// progressively should call [seedToolStates], [ensureDistro] and
  /// [refreshStatus] themselves instead.
  Future<void> init() async {
    seedToolStates();
    await ensureDistro();

    await Future.wait(AiWorkspaceTool.values.map(refreshStatus));
  }

  // -----------------------------------------------------------------------
  // Lifecycle operations
  // -----------------------------------------------------------------------

  /// Records a failed user action and makes it stick: [refreshStatus] will not
  /// touch this tool again until [clearError] runs. A failed install used to
  /// be erased by the very next background probe, which reported the tool as
  /// plain `notInstalled` with no message.
  void _recordActionFailure(AiWorkspaceTool tool, String? message) {
    final state = _toolStates[tool];
    if (state == null) return;
    state.status = ToolStatus.error;
    state.errorMessage = message;
    state.errorSticky = true;
  }

  /// Hands the tool back to the status probe after a sticky failure. Every
  /// explicit user action calls this — install, start, stop, and the UI's
  /// dismiss affordance. [status] falls back to the last *confirmed* answer
  /// rather than a guess, since an error is never cached.
  void clearError(AiWorkspaceTool tool) {
    final state = _toolStates[tool];
    if (state == null) return;
    state.errorMessage = null;
    state.errorSticky = false;
    if (state.status != ToolStatus.error) return;
    final cached = _loadCachedStatus(tool);
    state.status = (cached == null || cached == ToolStatus.error)
        ? ToolStatus.notInstalled
        : cached;
  }

  /// Install a workspace tool.
  Future<bool> install(AiWorkspaceTool tool) async {
    if (_installing.contains(tool)) return false;
    // An explicit retry owns the card again; the previous failure is history.
    clearError(tool);
    _installing.add(tool);
    try {
      return await _install(tool);
    } finally {
      _installing.remove(tool);
    }
  }

  Future<bool> _install(AiWorkspaceTool tool) async {
    await ensureDistro();
    final config = _toolConfigs[tool]!;

    if (tool == AiWorkspaceTool.openWebUi) {
      try {
        await _ensureDockerReady();
      } catch (e) {
        _recordActionFailure(tool, e.toString());
        return false;
      }
    }

    Notify.message(
      (tool == AiWorkspaceTool.openWebUi
              ? 'ai-workspace-pulling-image-text'
              : 'ai-workspace-installing-text')
          .i18n([config.name]),
      loading: true,
    );

    final request = ExecutionRequest(
      command: 'wsl',
      // pipefail: `curl ... | sh` otherwise exits 0 even when curl fails.
      arguments: _wslArgs('set -o pipefail; ${config.installCommand}'),
      timeout: const Duration(minutes: 5),
    );

    try {
      final result = await _broker.run(request);
      if (result.isSuccess) {
        final state = _toolStates[tool];
        state?.status = ToolStatus.stopped;
        state?.installPath = config.defaultInstallPath;
        state?.errorMessage = null;
        state?.errorSticky = false;
        state?.checked = true;
        state?.hasKnownStatus = true;
        _persistConfirmedState(tool);
        Notify.message(
            'ai-workspace-install-success-text'.i18n([config.name]));
        return true;
      } else {
        _recordActionFailure(tool, result.stderr);
        Notify.message(
            'ai-workspace-install-failed-text'.i18n([config.name]));
        return false;
      }
    } catch (e) {
      _recordActionFailure(tool, e.toString());
      Notify.message('ai-workspace-install-failed-text'.i18n([config.name]));
      return false;
    }
  }

  /// Start a running tool instance.
  Future<bool> start(AiWorkspaceTool tool) async {
    final state = _toolStates[tool];
    if (state == null || state.status == ToolStatus.notInstalled) {
      return false;
    }

    // An explicit start is a user action: it takes the card back from any
    // sticky failure left by the previous attempt.
    clearError(tool);

    await ensureDistro();
    // Must be held before the tool starts, or the distro tears the service
    // back down as soon as this call returns.
    await ensureKeepAlive();
    final config = _toolConfigs[tool]!;

    if (tool == AiWorkspaceTool.openWebUi) {
      try {
        await _ensureDockerReady();
      } catch (e) {
        _recordActionFailure(tool, e.toString());
        return false;
      }
    }

    Notify.message('ai-workspace-starting-text'.i18n([config.name]),
        loading: true);

    final request = ExecutionRequest(
      command: 'wsl',
      arguments: _wslArgs(config.startCommand),
      timeout: const Duration(minutes: 2),
    );

    try {
      final result = await _broker.run(request);
      if (result.isSuccess) {
        state.status = ToolStatus.running;
        state.lastStarted = DateTime.now();
        state.errorMessage = null;
        state.errorSticky = false;
        state.checked = true;
        state.hasKnownStatus = true;
        _persistConfirmedState(tool);
        Notify.message('ai-workspace-started-text'.i18n([config.name]));
        // The start command returning is not the tool serving. A tool with a
        // health gate has to be asked, or the card claims running for the
        // whole ~2 minute migration window and "Open Dashboard" walks the
        // user straight into the failure the gate exists to prevent.
        if (config.healthCheck != null) {
          await refreshStatus(tool);
        }
        return true;
      } else {
        _recordActionFailure(tool, result.stderr);
        Notify.message('ai-workspace-start-failed-text'.i18n([config.name]));
        return false;
      }
    } catch (e) {
      _recordActionFailure(tool, e.toString());
      Notify.message('ai-workspace-start-failed-text'.i18n([config.name]));
      return false;
    }
  }

  /// Stop a running tool instance.
  Future<bool> stop(AiWorkspaceTool tool) async {
    // Another explicit action — releases any sticky failure for this tool.
    clearError(tool);
    await ensureDistro();
    final config = _toolConfigs[tool]!;
    final request = ExecutionRequest(
      command: 'wsl',
      arguments: _wslArgs(config.stopCommand),
      timeout: const Duration(minutes: 1),
    );

    try {
      final result = await _broker.run(request);
      if (result.isSuccess) {
        _toolStates[tool]?.status = ToolStatus.stopped;
        _toolStates[tool]?.lastStopped = DateTime.now();
        _toolStates[tool]?.errorMessage = null;
        _toolStates[tool]?.checked = true;
        _toolStates[tool]?.hasKnownStatus = true;
        _persistConfirmedState(tool);
        return true;
      } else {
        _toolStates[tool]?.errorMessage = result.stderr;
        return false;
      }
    } catch (e) {
      _toolStates[tool]?.errorMessage = e.toString();
      return false;
    }
  }

  /// Uninstall a workspace tool.
  Future<bool> uninstall(AiWorkspaceTool tool) async {
    final state = _toolStates[tool];
    if (state != null && state.status == ToolStatus.running) {
      await stop(tool);
    }
    // Explicit action, and the closing refreshStatus() below would otherwise
    // be skipped while a sticky failure is showing.
    clearError(tool);

    try {
      await ensureDistro(forUninstall: true);
    } catch (e) {
      _toolStates[tool]?.errorMessage = e.toString();
      return false;
    }

    final config = _toolConfigs[tool]!;
    String uninstallCmd;
    if (config.defaultInstallPath.startsWith('docker://')) {
      final imageName = config.defaultInstallPath.substring('docker://'.length);
      uninstallCmd =
          'docker rm -f $imageName && docker rmi ghcr.io/open-webui/$imageName:latest';
    } else if (tool == AiWorkspaceTool.hermesAgent) {
      // No documented uninstall command — remove every known install root.
      uninstallCmd = 'pkill -f \'[h]ermes.*gateway\' >/dev/null 2>&1; '
          'rm -rf \$HOME/.hermes /usr/local/lib/hermes-agent; hash -r';
    } else if (tool == AiWorkspaceTool.openClaw) {
      // Covers both install methods: git wrapper and global npm.
      uninstallCmd = 'pkill -f \'[o]penclaw\' >/dev/null 2>&1; '
          'rm -f \$HOME/.local/bin/openclaw; '
          'npm uninstall -g openclaw >/dev/null 2>&1 || true; hash -r';
    } else {
      uninstallCmd = 'rm -rf ${config.defaultInstallPath}';
    }

    final request = ExecutionRequest(
      command: 'wsl',
      arguments: _wslArgs(uninstallCmd),
      timeout: const Duration(minutes: 2),
    );

    try {
      final result = await _broker.run(request);
      if (result.isSuccess) {
        // Clears installPath too — see the ToolState.status setter.
        _toolStates[tool]?.status = ToolStatus.notInstalled;
      } else {
        _toolStates[tool]?.errorMessage = result.stderr;
        return false;
      }
    } catch (e) {
      _toolStates[tool]?.errorMessage = e.toString();
      return false;
    }

    await refreshStatus(tool);
    return true;
  }

  /// Builds the "is this still installed" check for [installPath].
  static String _existsCheck(String installPath) {
    if (installPath.startsWith('docker://')) {
      final container = installPath.substring('docker://'.length);
      return 'docker inspect $container >/dev/null 2>&1 && echo exists || echo missing';
    }
    if (installPath.startsWith('cmd://')) {
      // PATH check, not a path check: `~` does not expand inside double
      // quotes, so `[ -d "~/.foo" ]` never matches.
      final binary = installPath.substring('cmd://'.length);
      return 'command -v $binary >/dev/null 2>&1 && echo exists || echo missing';
    }
    return '[ -d $installPath ] && echo exists || echo missing';
  }

  Future<void> refreshStatus(AiWorkspaceTool tool) async {
    // An install in flight is the authority on this tool's state. Probing
    // mid-install reports "missing" and would persist notInstalled over a
    // download that is still running.
    if (_installing.contains(tool)) return;

    // A failed install or start is the user's to read. This probe runs
    // immediately afterwards and would report the tool as plain "not
    // installed" with no message, so the reason it failed never reached the
    // screen. Only an explicit action ([clearError]) hands the card back.
    final failed = _toolStates[tool];
    if (failed != null && failed.errorSticky) {
      failed.checked = true;
      failed.hasKnownStatus = true;
      return;
    }

    await ensureDistro();
    final config = _toolConfigs[tool]!;
    final isDockerBacked = config.defaultInstallPath.startsWith('docker://');

    // `service docker start` returns as soon as the init script forks, but
    // dockerd needs several seconds more to create its socket. Probing in
    // that window fails, and the failure is indistinguishable from "the
    // container is gone" — which is how an installed tool ends up cached as
    // notInstalled after a reboot. Wait for the daemon, and if it never
    // comes up say so rather than guessing.
    final dockerPrefix = isDockerBacked
        ? 'service docker start >/dev/null 2>&1; '
            '$_kDockerWaitLoop'
            'docker info >/dev/null 2>&1 || { echo $_kDockerDownMarker; exit 0; }; '
        : '';

    // Status, health and existence check in one shell invocation — each
    // `wsl -d` call carries real spawn overhead. The health gate only runs
    // once the tool is up, so a tool without one costs nothing.
    final healthGate = config.healthCheck ?? 'echo running';
    final combinedCommand = '$dockerPrefix'
        '_s=\$(${config.statusCheck}); '
        'if [ \$_s = running ]; then $healthGate; '
        'else ${_existsCheck(config.defaultInstallPath)}; fi';

    final request = ExecutionRequest(
      command: 'wsl',
      // Covers the daemon wait above plus the checks themselves.
      // A cold distro takes several seconds just to boot before it runs
      // anything, so 10s was routinely too tight for the first probe.
      timeout: isDockerBacked
          ? const Duration(seconds: 40)
          : const Duration(seconds: 20),
      arguments: _wslArgs(combinedCommand),
    );

    try {
      final result = await _broker.run(request);
      final rawOutput = result.stdout.trim().toLowerCase();
      if (result.isSuccess && rawOutput.contains(_kDockerDownMarker)) {
        // Docker never came up. That says nothing about whether the tool is
        // installed, so keep whatever was last confirmed and report the real
        // problem instead of silently downgrading to notInstalled.
        _toolStates[tool]?.errorMessage = 'ai-workspace-docker-unavailable-text'.i18n();
      } else if (result.isSuccess) {
        final output = rawOutput;
        // `starting` first: it is the health gate's answer for a container
        // that is up but still migrating, and must not be read as running.
        if (output.contains('starting')) {
          _toolStates[tool]?.status = ToolStatus.starting;
        } else if (output.contains('running')) {
          _toolStates[tool]?.status = ToolStatus.running;
        } else if (output.contains('exists') || output.contains('stopped')) {
          // `stopped` comes from the health gate (up, but unhealthy) — the
          // tool is installed either way, so it must not fall through to
          // notInstalled and lose its install path.
          _toolStates[tool]?.status = ToolStatus.stopped;
        } else {
          // The setter drops installPath with it: "Not installed" and
          // "Installed: <path>" must never appear on the same card.
          _toolStates[tool]?.status = ToolStatus.notInstalled;
        }
        // Any answer other than notInstalled is a confirmation of exactly the
        // path the check was built from, so re-assert it — the probe that
        // last said notInstalled cleared it.
        if (_toolStates[tool]?.status != ToolStatus.notInstalled) {
          _toolStates[tool]?.installPath = config.defaultInstallPath;
        }
        _toolStates[tool]?.errorMessage = null;
        _persistConfirmedState(tool);
      } else if (_indicatesMissingDistro(result.stderr)) {
        // An explicit WSL error code is still a confirmed answer.
        _toolStates[tool]?.status = ToolStatus.notInstalled;
        _toolStates[tool]?.errorMessage = null;
        _persistConfirmedState(tool);
      } else {
        // Not a confirmed signal — leave the cache alone.
        _toolStates[tool]?.status = ToolStatus.error;
        _toolStates[tool]?.errorMessage = result.stderr;
      }
    } catch (e) {
      // A timeout or a dead WSL call says nothing about whether the tool is
      // installed. Claiming notInstalled here is how a cold distro — where the
      // first call routinely exceeds the timeout — makes an installed tool
      // read as missing. Keep the last known status and report the failure.
      _toolStates[tool]?.errorMessage = e.toString();
    } finally {
      // Set on every path: the UI cares that a check was attempted.
      _toolStates[tool]?.checked = true;
      _toolStates[tool]?.hasKnownStatus = true;
    }
  }

  // ---------------------------------------------------------------------
  // Background pre-fetch
  // ---------------------------------------------------------------------

  Future<void>? _initFuture;

  /// Seeds state and probes every tool, memoized. Kicked off fire-and-forget
  /// from app startup so the screen has results by the time it opens;
  /// concurrent callers join the same run.
  Future<void> ensureInitialized() {
    return _initFuture ??= _runInitialCheck();
  }

  Future<void> _runInitialCheck() async {
    if (_toolStates.isEmpty) {
      seedToolStates();
    }
    await ensureDistro();
    await Future.wait(AiWorkspaceTool.values.map(refreshStatus));
  }

  /// Static port URL, no WSL call. Only valid for tools without a
  /// [ToolConfig.dashboardCommand] — use [getDashboardUrl] for the rest.
  String? getUrl(AiWorkspaceTool tool) {
    final state = _toolStates[tool];
    if (state == null || state.status != ToolStatus.running) {
      return null;
    }

    return 'http://localhost:${state.port}';
  }

  /// Starts the dashboard server if the tool needs one, then waits until
  /// the URL actually answers. Null means "could not open" — a container
  /// reporting "Up" does not mean its web server is serving yet.
  Future<String?> getDashboardUrl(AiWorkspaceTool tool) async {
    final state = _toolStates[tool];
    if (state == null || state.status != ToolStatus.running) {
      return null;
    }

    final config = _toolConfigs[tool]!;
    final url = config.dashboardCommand == null
        ? getUrl(tool)
        : await _runDashboardCommand(tool, config);
    // "Could not open the dashboard" on its own is untraceable; say which
    // step gave up.
    if (url == null) {
      state.errorMessage = 'No dashboard URL from: ${config.dashboardCommand}';
      return null;
    }
    if (!await _waitUntilReachable(url)) {
      state.errorMessage = 'Dashboard URL not reachable from Windows: $url';
      return null;
    }
    state.errorMessage = null;
    return url;
  }

  Future<String?> _runDashboardCommand(
      AiWorkspaceTool tool, ToolConfig config) async {
    await ensureDistro();

    // The command runs in the foreground and its output is parsed in Dart.
    // Doing the extraction in shell meant grep patterns, redirections and
    // `$(...)` had to survive Dart's Windows argument escaping on the way into
    // wsl.exe; they did not, and the failure was silent. Keeping the shell
    // side to a bare command removes that whole class of bug.
    final request = ExecutionRequest(
      command: 'wsl',
      arguments: _wslArgs(config.dashboardCommand!),
      timeout: const Duration(seconds: 40),
    );

    try {
      final result = await _broker.run(request);
      return _firstServiceUrl('${result.stdout}\n${result.stderr}');
    } catch (_) {
      return null;
    }
  }

  /// Picks the tool's own URL out of [output].
  ///
  /// Prefers a loopback address: these tools also print documentation links,
  /// and those are reachable, so a naive match opens the docs instead.
  static String? _firstServiceUrl(String output) {
    final urls = RegExp(r'https?://[^\s]+')
        .allMatches(output)
        .map((m) => m.group(0)!)
        // Trailing punctuation from prose lines.
        .map((u) => u.replaceAll(RegExp(r'[.,)\]]+$'), ''))
        .toList();
    if (urls.isEmpty) return null;
    return urls.firstWhere(
      (u) => u.contains('127.0.0.1') || u.contains('localhost'),
      orElse: () => urls.first,
    );
  }

  /// Polls [url] until something actually answers, or [timeout] elapses.
  Future<bool> _waitUntilReachable(
    String url, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      if (await _isReachable(url)) return true;
      if (DateTime.now().isAfter(deadline)) return false;
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }
}
