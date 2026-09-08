// Managing containers on whatever engine the host already has.
//
// The decision behind this file (bostrot/ai-tasks#57): the app is a *front
// end* for an engine the user installed, not an engine of its own. It shells
// out to `docker` or `podman` on the host — the same binary the user types in
// a terminal — instead of bundling a runtime or installing one inside a
// distro/VM and proxying through it. Nothing to keep in sync with the engine's
// releases, nothing to tear down when the app is uninstalled, and a container
// started here is the same object the user's own `docker ps` shows.
//
// Both engines take the same subcommands, so one service drives either; the
// engine is a value on the service rather than a subclass.

import 'dart:async';

import 'package:wsl2distromanager/api/containers/container_models.dart';
import 'package:wsl2distromanager/api/execution/broker.dart';
import 'package:wsl2distromanager/api/execution/models.dart';
import 'package:wsl2distromanager/api/remote_target.dart';
import 'package:wsl2distromanager/api/shell.dart';
import 'package:wsl2distromanager/components/helpers.dart';

/// Preference key holding the engine the user pinned, as an executable name.
const String containerEnginePrefKey = 'ContainerEngine';

/// Field separator of the `ps` template below. A tab cannot occur inside any
/// of the fields the engines print, which a space very much can (`Status` is
/// "Exited (0) 3 minutes ago").
const String _fieldSeparator = '\t';

/// The `ps --format` template. Fields both engines document, in one order.
const String _psTemplate = '{{.ID}}\t{{.Names}}\t{{.Image}}\t{{.State}}'
    '\t{{.Status}}\t{{.Ports}}';

/// Container names and ids accepted from callers. Matches what the engines
/// themselves allow, and — because it cannot start with `-` — keeps a crafted
/// name from arriving as another flag on the command line.
final RegExp _refPattern = RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_.-]*$');

/// Drives `docker`/`podman` on the host.
class ContainerService {
  /// Every engine command goes through the broker rather than `Process.run`.
  /// A plain `run` hands back no handle, so a timeout could only *stop
  /// waiting* on a hung `docker ps` and leave the child behind — the same
  /// leak that once orphaned hundreds of `wsl.exe` processes (see
  /// `ExecutionBroker.run`). The broker reaps it, and strips the engines'
  /// ANSI colouring out of the output on the way.
  final ExecutionBroker _broker;

  /// How long any single engine command may take before it is abandoned.
  final Duration timeout;

  ContainerService({
    Shell? shell,
    ExecutionBroker? broker,
    this.timeout = const Duration(seconds: 30),
  }) : _broker = broker ?? ExecutionBroker(shell: shell ?? ProcessShell());

  /// Engines found on this host, cached for the life of the service: probing
  /// costs two process launches and the answer only changes when the user
  /// installs something.
  List<ContainerEngine>? _available;

  /// Whether the app is driving a remote Windows host over SSH. The container
  /// commands follow the rest of the app: with a remote target configured the
  /// engine that matters is the remote one, not the laptop's.
  bool get _useRemote {
    try {
      final enabled = prefs.getBool('UseRemoteWSL') ?? false;
      final target = prefs.getString('RemoteWSLTarget')?.trim() ?? '';
      return enabled && isValidRemoteTarget(target);
    } catch (_) {
      // Preferences not initialised (tests, early startup) — stay local.
      return false;
    }
  }

  String get _remoteTarget {
    try {
      return prefs.getString('RemoteWSLTarget')?.trim() ?? '';
    } catch (_) {
      return '';
    }
  }

  /// The engine the user pinned in settings, or null when they never did.
  ContainerEngine? get preferredEngine {
    try {
      return ContainerEngine.byExecutable(
          prefs.getString(containerEnginePrefKey));
    } catch (_) {
      return null;
    }
  }

  /// Pin [engine] as the one to use, or clear the pin with null.
  Future<void> setPreferredEngine(ContainerEngine? engine) async {
    if (engine == null) {
      await prefs.remove(containerEnginePrefKey);
    } else {
      await prefs.setString(containerEnginePrefKey, engine.executable);
    }
  }

  /// Forget the probe result, so the next call looks for engines again. Used
  /// by the Containers screen's refresh: installing Docker while the app is
  /// open must not need a restart.
  void invalidateEngineCache() => _available = null;

  /// Every engine installed on the host, in [ContainerEngine] order.
  ///
  /// "Installed" means the binary answered `--version`. An engine whose
  /// daemon is down still shows up here — that failure belongs to [list],
  /// which can say *why* instead of pretending nothing is installed.
  Future<List<ContainerEngine>> availableEngines() async {
    final cached = _available;
    if (cached != null) return cached;
    final found = <ContainerEngine>[];
    for (final engine in ContainerEngine.values) {
      final result = await _run(engine, ['--version']);
      if (result.exitCode == 0) found.add(engine);
    }
    return _available = found;
  }

  /// The engine commands run against: the pinned one when it is installed,
  /// otherwise the first one found. Null when the host has none.
  Future<ContainerEngine?> activeEngine() async {
    final available = await availableEngines();
    if (available.isEmpty) return null;
    final preferred = preferredEngine;
    if (preferred != null && available.contains(preferred)) return preferred;
    return available.first;
  }

  /// All containers known to [engine] (or to [activeEngine] when omitted),
  /// stopped ones included unless [runningOnly] is set.
  ///
  /// Throws [ContainerException] when no engine is installed or the engine
  /// refuses to answer — a stopped Docker daemon is the common case, and its
  /// own message is the one worth showing.
  Future<List<ContainerInfo>> list({
    ContainerEngine? engine,
    bool runningOnly = false,
  }) async {
    final target = engine ?? await activeEngine();
    if (target == null) throw const ContainerException(_noEngineMessage);
    final result = await _run(target, [
      'ps',
      if (!runningOnly) '--all',
      '--no-trunc',
      '--format',
      _psTemplate,
    ]);
    if (result.exitCode != 0) {
      throw ContainerException(_failureText(target, result, 'ps'));
    }
    return parsePsOutput(result.stdout, target);
  }

  /// Containers across every installed engine. A host with both Docker and
  /// Podman gets one list, each row carrying the engine that reported it.
  ///
  /// Engines that fail are skipped rather than failing the whole call — with
  /// Podman installed but never initialised, Docker's containers must still
  /// render. When *every* engine fails, all of their messages are thrown
  /// together: "podman machine is not running" alone would send someone
  /// after the wrong engine when Docker is the one they use.
  Future<List<ContainerInfo>> listAll({bool runningOnly = false}) async {
    final engines = await availableEngines();
    if (engines.isEmpty) throw const ContainerException(_noEngineMessage);
    final containers = <ContainerInfo>[];
    final failures = <String>[];
    var anySucceeded = false;
    for (final engine in engines) {
      try {
        containers.addAll(await list(engine: engine, runningOnly: runningOnly));
        anySucceeded = true;
      } on ContainerException catch (e) {
        failures.add(e.message);
      }
    }
    if (!anySucceeded && failures.isNotEmpty) {
      throw ContainerException(failures.join('\n\n'));
    }
    return containers;
  }

  /// Start a stopped container.
  Future<String> start(ContainerEngine engine, String ref) =>
      _lifecycle(engine, 'start', ref);

  /// Stop a running container, giving it the engine's default grace period.
  Future<String> stop(ContainerEngine engine, String ref) =>
      _lifecycle(engine, 'stop', ref);

  /// Restart a container, running or not.
  Future<String> restart(ContainerEngine engine, String ref) =>
      _lifecycle(engine, 'restart', ref);

  /// Delete a container. A running one is only removed with [force], which
  /// kills it first — the engines refuse otherwise, and that refusal is the
  /// safety net worth keeping.
  Future<String> remove(ContainerEngine engine, String ref,
      {bool force = false}) async {
    _checkRef(ref);
    final result = await _run(engine, ['rm', if (force) '--force', ref]);
    if (result.exitCode != 0) {
      throw ContainerException(_failureText(engine, result, 'rm $ref'));
    }
    return result.stdout.trim();
  }

  /// The last [lines] of a container's log.
  Future<String> logs(ContainerEngine engine, String ref,
      {int lines = 200}) async {
    _checkRef(ref);
    if (lines <= 0) {
      throw ArgumentError.value(lines, 'lines', 'must be greater than zero');
    }
    final result = await _run(engine, ['logs', '--tail', '$lines', ref]);
    if (result.exitCode != 0) {
      throw ContainerException(_failureText(engine, result, 'logs $ref'));
    }
    // Engines write a container's stderr to *their* stderr, so a log that is
    // only diagnostics would come back empty without this.
    final merged = [result.stdout.trimRight(), result.stderr.trimRight()]
        .where((part) => part.isNotEmpty)
        .join('\n');
    return merged;
  }

  /// Run [command] inside a running container through its `sh`, returning
  /// stdout and stderr together.
  Future<String> exec(ContainerEngine engine, String ref, String command) async {
    _checkRef(ref);
    if (command.trim().isEmpty) {
      throw ArgumentError.value(command, 'command', 'must not be empty');
    }
    final result = await _run(engine, ['exec', ref, 'sh', '-c', command]);
    final output = [result.stdout.trimRight(), result.stderr.trimRight()]
        .where((part) => part.isNotEmpty)
        .join('\n');
    if (result.exitCode != 0) {
      throw ContainerException(output.isEmpty
          ? _failureText(engine, result, 'exec $ref')
          : 'Command exited with ${result.exitCode}:\n$output');
    }
    return output;
  }

  /// The engine's own JSON description of a container.
  Future<String> inspect(ContainerEngine engine, String ref) async {
    _checkRef(ref);
    final result =
        await _run(engine, ['inspect', ref]);
    if (result.exitCode != 0) {
      throw ContainerException(_failureText(engine, result, 'inspect $ref'));
    }
    return result.stdout.trim();
  }

  Future<String> _lifecycle(
      ContainerEngine engine, String verb, String ref) async {
    _checkRef(ref);
    final result = await _run(engine, [verb, ref]);
    if (result.exitCode != 0) {
      throw ContainerException(_failureText(engine, result, '$verb $ref'));
    }
    return result.stdout.trim();
  }

  void _checkRef(String ref) {
    if (!_refPattern.hasMatch(ref)) {
      throw ArgumentError.value(ref, 'ref', 'not a valid container name or id');
    }
  }

  /// Run one engine command, locally or over SSH.
  ///
  /// Never throws for an ordinary failure: a missing binary and a refusing
  /// daemon both come back as a non-zero [_EngineResult], because "docker is
  /// not installed" is the answer [availableEngines] is asking for. A timeout
  /// is the exception — there is no exit code to report, and the caller has
  /// to say so rather than treat it as "no containers".
  Future<_EngineResult> _run(
    ContainerEngine engine,
    List<String> arguments,
  ) async {
    final remote = _useRemote;
    final executable = remote ? 'ssh' : engine.executable;
    final args = remote
        ? sshRemoteCommand(_remoteTarget, engine.executable, arguments)
        : arguments;
    final result = await _broker.run(ExecutionRequest(
      command: executable,
      arguments: args,
      timeout: timeout,
      runInShell: false,
    ));
    if (result.error is TimeoutException) {
      throw ContainerException(
          '${engine.label} did not answer within ${timeout.inSeconds}s: '
          '${engine.executable} ${arguments.join(' ')}');
    }
    return _EngineResult(
      exitCode: result.exitCode,
      stdout: result.stdout,
      stderr: result.stderr,
    );
  }

  String _failureText(
      ContainerEngine engine, _EngineResult result, String what) {
    final detail = result.stderr.trim().isNotEmpty
        ? result.stderr.trim()
        : result.stdout.trim();
    final suffix = detail.isEmpty ? '' : '\n$detail';
    return '${engine.label} failed to run "$what" '
        '(exit ${result.exitCode}).$suffix';
  }

  static const String _noEngineMessage =
      'No container engine found. Install Docker or Podman and make sure its '
      'command is on your PATH.';

  /// Message shown when the host has no engine at all. Public so the UI and
  /// the MCP tools say the same thing.
  static String get noEngineMessage => _noEngineMessage;

  /// Turn `ps --format` output into rows.
  ///
  /// Static and public because the parsing is the part worth testing on its
  /// own, and because the AI Workspace reads the same shape. Lines that do not
  /// carry at least an id and a name are skipped: engines print warnings on
  /// stdout ("Emulate Docker CLI using podman…") and one of those must not
  /// become a container row.
  static List<ContainerInfo> parsePsOutput(
      String output, ContainerEngine engine) {
    final containers = <ContainerInfo>[];
    for (final rawLine in output.split('\n')) {
      final line = rawLine.trimRight();
      if (line.trim().isEmpty) continue;
      final fields = line.split(_fieldSeparator);
      if (fields.length < 2) continue;
      final id = fields[0].trim();
      final name = fields[1].trim();
      if (id.isEmpty && name.isEmpty) continue;
      String field(int index) =>
          index < fields.length ? fields[index].trim() : '';
      final status = field(4);
      final rawState = field(3);
      containers.add(ContainerInfo(
        id: id,
        name: name,
        image: field(2),
        // Older engines leave `.State` empty; the first word of `.Status`
        // ("Up 2 hours", "Exited (0) …") says the same thing.
        state: ContainerState.parse(
            rawState.isNotEmpty ? rawState : status.split(' ').first),
        status: status,
        ports: field(5),
        engine: engine,
      ));
    }
    return containers;
  }
}

/// Engine output normalised to text, whatever encoding the shell handed back.
class _EngineResult {
  final int exitCode;
  final String stdout;
  final String stderr;

  const _EngineResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });
}
