// Install/start/status lifecycle for the AI Workspace tools. Every command
// runs inside the dedicated [kAiWorkspaceDistro] Ubuntu distro.

import 'package:dio/dio.dart';
import 'package:localization/localization.dart';

import '../../components/helpers.dart';
import '../../components/notify.dart';
import '../execution/broker.dart';
import '../execution/models.dart';

/// The dedicated WSL distro name used for AI workspace tools.
const String kAiWorkspaceDistro = 'ai-workspace';

/// Supported AI workspace tools.
enum AiWorkspaceTool { hermesAgent, openClaw, openWebUi }

/// Status of a workspace tool instance.
enum ToolStatus { notInstalled, stopped, running, error }

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

  const ToolConfig({
    required this.name,
    required this.installCommand,
    required this.startCommand,
    required this.stopCommand,
    required this.statusCheck,
    required this.port,
    required this.defaultInstallPath,
    this.dashboardCommand,
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
    startCommand: 'pkill -f "[h]ermes.*gateway" >/dev/null 2>&1; '
        'mkdir -p "\$HOME/.hermes"; '
        'setsid hermes gateway </dev/null >>"\$HOME/.hermes/gateway.log" 2>&1 & '
        'disown; sleep 1; pgrep -f "[h]ermes.*gateway" >/dev/null',
    stopCommand: 'pkill -f "[h]ermes.*gateway" || true',
    statusCheck:
        'pgrep -f "[h]ermes.*gateway" > /dev/null && echo running || echo stopped',
    port: 9119,
    defaultInstallPath: 'cmd://hermes',
    dashboardCommand: 'hermes dashboard',
  ),
  AiWorkspaceTool.openClaw: ToolConfig(
    name: 'OpenClaw',
    installCommand:
        'curl -fsSL https://openclaw.ai/install.sh | bash -s -- --no-onboard --no-prompt',
    // There is no plain `gateway start`; install --force + restart is the
    // documented way to (re)start it.
    startCommand: 'openclaw gateway install --force >/dev/null 2>&1; '
        'openclaw gateway restart >/dev/null 2>&1; '
        'sleep 1; pgrep -f "[o]penclaw" >/dev/null',
    stopCommand: 'pkill -f "[o]penclaw" || true',
    statusCheck:
        'pgrep -f "[o]penclaw" > /dev/null && echo running || echo stopped',
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
        'docker ps --filter "name=open-webui" | grep -q Up && echo running || echo stopped',
    port: 8083,
    defaultInstallPath: 'docker://open-webui',
  ),
};

/// State tracker for a single tool instance.
class ToolState {
  final AiWorkspaceTool tool;
  ToolStatus status;
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

  ToolState({
    required this.tool,
    this.status = ToolStatus.notInstalled,
    this.installPath,
    required this.port,
    this.lastStarted,
    this.lastStopped,
    this.errorMessage,
    this.checked = false,
    this.hasKnownStatus = false,
  });
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

  AiWorkspaceService({
    required ExecutionBroker broker,
    DashboardReachabilityChecker? reachabilityChecker,
  })  : _broker = broker,
        _isReachable = reachabilityChecker ?? _defaultReachabilityCheck;

  Map<AiWorkspaceTool, ToolState> get toolStates =>
      Map.unmodifiable(_toolStates);

  ToolState? getState(AiWorkspaceTool tool) => _toolStates[tool];

  // -----------------------------------------------------------------------
  // Distro management
  // -----------------------------------------------------------------------

  /// Creates the distro if missing. With [forUninstall] it must already
  /// exist and the call fails instead.
  Future<void> ensureDistro({bool forUninstall = false}) async {
    if (_distroReady) return;

    final listResult = await _broker.run(ExecutionRequest(
      command: 'wsl',
      arguments: ['--list', '--quiet'],
      timeout: const Duration(seconds: 10),
    ));

    if (listResult.isSuccess) {
      final distros = listResult.stdout
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (distros.contains(kAiWorkspaceDistro)) {
        _distroReady = true;
        return;
      }
    }

    if (forUninstall) {
      throw Exception(
          'AI workspace distro is not installed. Cannot uninstall.');
    }

    await _createUbuntuDistro();
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

    throw Exception(
        'Failed to create the AI workspace distro: ${installResult.stderr}');
  }

  /// Runs as root — this distro is automation-only.
  List<String> _wslArgs(String shellCommand) {
    return ['-d', kAiWorkspaceDistro, '-u', 'root', 'bash', '-c', shellCommand];
  }

  /// Installs docker.io on first use — the base Ubuntu image has no Docker.
  Future<void> _ensureDockerReady() async {
    if (_dockerReady) return;

    Notify.message('ai-workspace-docker-setup-text'.i18n(), loading: true);
    const setupCommand = 'command -v docker >/dev/null 2>&1 || '
        '(apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker.io); '
        'service docker status >/dev/null 2>&1 || service docker start';

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
        installPath:
            cachedStatus != null ? prefs.getString(_installPathPrefsKey(tool)) : null,
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

  /// Install a workspace tool.
  Future<bool> install(AiWorkspaceTool tool) async {
    await ensureDistro();
    final config = _toolConfigs[tool]!;

    if (tool == AiWorkspaceTool.openWebUi) {
      try {
        await _ensureDockerReady();
      } catch (e) {
        _toolStates[tool]?.errorMessage = e.toString();
        _toolStates[tool]?.status = ToolStatus.error;
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
        state?.checked = true;
        state?.hasKnownStatus = true;
        _persistConfirmedState(tool);
        Notify.message(
            'ai-workspace-install-success-text'.i18n([config.name]));
        return true;
      } else {
        _toolStates[tool]?.errorMessage = result.stderr;
        _toolStates[tool]?.status = ToolStatus.error;
        Notify.message(
            'ai-workspace-install-failed-text'.i18n([config.name]));
        return false;
      }
    } catch (e) {
      _toolStates[tool]?.errorMessage = e.toString();
      _toolStates[tool]?.status = ToolStatus.error;
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

    await ensureDistro();
    final config = _toolConfigs[tool]!;

    if (tool == AiWorkspaceTool.openWebUi) {
      try {
        await _ensureDockerReady();
      } catch (e) {
        state.errorMessage = e.toString();
        state.status = ToolStatus.error;
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
        state.checked = true;
        state.hasKnownStatus = true;
        _persistConfirmedState(tool);
        Notify.message('ai-workspace-started-text'.i18n([config.name]));
        return true;
      } else {
        state.errorMessage = result.stderr;
        state.status = ToolStatus.error;
        Notify.message('ai-workspace-start-failed-text'.i18n([config.name]));
        return false;
      }
    } catch (e) {
      state.errorMessage = e.toString();
      state.status = ToolStatus.error;
      Notify.message('ai-workspace-start-failed-text'.i18n([config.name]));
      return false;
    }
  }

  /// Stop a running tool instance.
  Future<bool> stop(AiWorkspaceTool tool) async {
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
      uninstallCmd = 'pkill -f "[h]ermes.*gateway" >/dev/null 2>&1; '
          'rm -rf "\$HOME/.hermes" /usr/local/lib/hermes-agent; hash -r';
    } else if (tool == AiWorkspaceTool.openClaw) {
      // Covers both install methods: git wrapper and global npm.
      uninstallCmd = 'pkill -f "[o]penclaw" >/dev/null 2>&1; '
          'rm -f "\$HOME/.local/bin/openclaw"; '
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
        _toolStates[tool]?.status = ToolStatus.notInstalled;
        _toolStates[tool]?.installPath = null;
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
    return '[ -d "$installPath" ] && echo exists || echo missing';
  }

  Future<void> refreshStatus(AiWorkspaceTool tool) async {
    await ensureDistro();
    final config = _toolConfigs[tool]!;
    final isDockerBacked = config.defaultInstallPath.startsWith('docker://');

    // dockerd does not auto-start on distro boot; without this the checks
    // fail and a genuinely installed tool reads as "not installed".
    // Starting it is a no-op when already running.
    final dockerPrefix =
        isDockerBacked ? 'service docker start >/dev/null 2>&1; ' : '';

    // Status and existence check in one shell invocation — each `wsl -d`
    // call carries real spawn overhead.
    final combinedCommand = '$dockerPrefix'
        '_s=\$(${config.statusCheck}); '
        'if [ "\$_s" = "running" ]; then echo running; '
        'else ${_existsCheck(config.defaultInstallPath)}; fi';

    final request = ExecutionRequest(
      command: 'wsl',
      arguments: _wslArgs(combinedCommand),
      timeout: const Duration(seconds: 10),
    );

    try {
      final result = await _broker.run(request);
      if (result.isSuccess) {
        final output = result.stdout.trim().toLowerCase();
        if (output.contains('running')) {
          _toolStates[tool]?.status = ToolStatus.running;
        } else if (output.contains('exists')) {
          _toolStates[tool]?.status = ToolStatus.stopped;
        } else {
          _toolStates[tool]?.status = ToolStatus.notInstalled;
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
      // Same here: in-memory only, cache untouched.
      _toolStates[tool]?.status = ToolStatus.notInstalled;
      _toolStates[tool]?.errorMessage = null;
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
    if (url == null) return null;

    return await _waitUntilReachable(url) ? url : null;
  }

  Future<String?> _runDashboardCommand(
      AiWorkspaceTool tool, ToolConfig config) async {
    await ensureDistro();

    // Truncate first: a stale single-use pairing link must not be picked up.
    final logPath = '/tmp/ai-workspace-dashboard-${tool.name}.log';
    final command = ': > "$logPath"; '
        'setsid ${config.dashboardCommand} </dev/null >>"$logPath" 2>&1 & '
        'disown; '
        'for i in 1 2 3 4 5; do '
        'sleep 1; '
        'url=\$(grep -oE \'https?://[^"[:space:]]+\' "$logPath" | tail -1); '
        'if [ -n "\$url" ]; then echo "\$url"; exit 0; fi; '
        'done; '
        'exit 1';

    final request = ExecutionRequest(
      command: 'wsl',
      arguments: _wslArgs(command),
      timeout: const Duration(seconds: 15),
    );

    try {
      final result = await _broker.run(request);
      final url = result.stdout.trim();
      return (result.isSuccess && url.isNotEmpty) ? url : null;
    } catch (_) {
      return null;
    }
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
