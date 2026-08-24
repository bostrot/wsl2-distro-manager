// AI Workspace service for managing Hermes Agent, OpenClaw, and Open WebUI.
// Provides install/start/status lifecycle management for workspace tools.
// All commands run inside a dedicated Ubuntu WSL distro to guarantee curl/bash/docker availability.

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
  // Command that prints a dashboard URL to open, for tools whose web UI
  // isn't just "connect to a fixed port" (e.g. it needs its own server
  // started, or the URL includes a one-time auth token). Null for tools
  // where [port] alone is enough (Open WebUI).
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

/// Default tool configurations.
/// Commands assume Ubuntu environment (curl, bash, docker available).
const Map<AiWorkspaceTool, ToolConfig> _toolConfigs = {
  // get.hermes-agent.dev and install.openclaw.ai (the original URLs here)
  // never resolved — they were placeholders. Real project, real installer:
  // https://github.com/NousResearch/hermes-agent. Neither tool exposes a
  // simple fixed HTTP port like Open WebUI does; both run as a background
  // "gateway" process managed by their own CLI, so start/stop here shell out
  // to that CLI (with a setsid-detached fallback for hermes, which has no
  // documented gateway-stop subcommand) rather than assuming a `serve --port`
  // flag that never existed.
  AiWorkspaceTool.hermesAgent: ToolConfig(
    name: 'Hermes Agent',
    installCommand: 'curl -fsSL https://hermes-agent.nousresearch.com/install.sh '
        '| bash -s -- --non-interactive',
    // No confirmed `hermes gateway stop`, so start by killing any previous
    // instance first, then launch detached via setsid (not just `nohup &`,
    // which stays attached to the invoking shell's session and can be
    // reaped once this one-shot `wsl` call exits). Success is judged by
    // actually finding the process alive afterward, not by the launcher
    // command's own exit code, which would be 0 even if the gateway died
    // immediately.
    startCommand: 'pkill -f "[h]ermes.*gateway" >/dev/null 2>&1; '
        'mkdir -p "\$HOME/.hermes"; '
        'setsid hermes gateway </dev/null >>"\$HOME/.hermes/gateway.log" 2>&1 & '
        'disown; sleep 1; pgrep -f "[h]ermes.*gateway" >/dev/null',
    stopCommand: 'pkill -f "[h]ermes.*gateway" || true',
    statusCheck:
        'pgrep -f "[h]ermes.*gateway" > /dev/null && echo running || echo stopped',
    // Real, documented port for `hermes dashboard` (a separate web-UI
    // server, not the gateway itself) — see dashboardCommand below.
    port: 9119,
    // cmd:// checks PATH via `command -v` instead of a fixed install
    // directory — hermes's installer supports multiple layouts (FHS under
    // /usr/local for root, $HOME/.hermes otherwise), so the binary being on
    // PATH is the one thing guaranteed true across all of them.
    defaultInstallPath: 'cmd://hermes',
    // "hermes dashboard" starts its own machine-level management server
    // (independent of the gateway) at http://127.0.0.1:9119 by default —
    // https://hermes-agent.nousresearch.com/docs/user-guide/features/web-dashboard.
    dashboardCommand: 'hermes dashboard',
  ),
  // Real project: https://github.com/openclaw/openclaw. --no-onboard
  // --no-prompt are documented flags for unattended installs.
  AiWorkspaceTool.openClaw: ToolConfig(
    name: 'OpenClaw',
    installCommand:
        'curl -fsSL https://openclaw.ai/install.sh | bash -s -- --no-onboard --no-prompt',
    // `gateway install`/`gateway restart` are the documented lifecycle
    // commands the installer itself uses to (re)start the service; there's
    // no confirmed plain `gateway start`. Same "verify it's actually alive"
    // pattern as hermes above.
    startCommand: 'openclaw gateway install --force >/dev/null 2>&1; '
        'openclaw gateway restart >/dev/null 2>&1; '
        'sleep 1; pgrep -f "[o]penclaw" >/dev/null',
    stopCommand: 'pkill -f "[o]penclaw" || true',
    statusCheck:
        'pgrep -f "[o]penclaw" > /dev/null && echo running || echo stopped',
    // Real, documented port for the OpenClaw Control UI dashboard.
    port: 18789,
    defaultInstallPath: 'cmd://openclaw',
    // "openclaw dashboard" is the documented way to open *or reopen* the
    // Control UI — it prints a single-use pairing link (not just a bare
    // port URL), so it needs to actually run rather than being guessed at.
    // https://docs.openclaw.ai/web/dashboard
    dashboardCommand: 'openclaw dashboard',
  ),
  AiWorkspaceTool.openWebUi: ToolConfig(
    name: 'Open WebUI',
    // `docker rm -f` first makes this idempotent: if detection was ever
    // wrong about an existing container (see refreshStatus's docker-daemon
    // note above) and the user re-runs install, this won't hard-fail with
    // "name already in use" — it just replaces whatever was there.
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
  // Whether a *live* WSL check has completed this app session (regardless
  // of whether status came back confirmed-installed or confirmed-missing).
  // Distinct from [hasKnownStatus]: a tool can have known status (loaded
  // from the persisted cache) without ever having been live-checked yet
  // this session — used to decide whether a background refresh is still
  // owed for this tool, not whether the UI has something to show.
  bool checked;
  // Whether [status]/[installPath] reflect real information — either a
  // live check this session, or a persisted value from a previous one —
  // as opposed to just the constructor's blank default. Both a genuinely
  // unchecked tool and a confirmed-not-installed one start out reporting
  // ToolStatus.notInstalled, so status alone can't tell a UI whether it's
  // safe to show that as a real answer or whether it should show a
  // checking spinner instead.
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
        // Any real HTTP response — even a 4xx/5xx — means something is
        // actually listening and answering, which is all "reachable"
        // needs to mean here. We're not authenticating, just checking
        // there's a live server behind the URL before opening a browser
        // tab to it.
        validateStatus: (_) => true,
      ),
    );
    return response.statusCode != null;
  } catch (_) {
    // Connection refused/reset — nothing listening yet.
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

  /// Create service backed by the given [ExecutionBroker].
  AiWorkspaceService({
    required ExecutionBroker broker,
    DashboardReachabilityChecker? reachabilityChecker,
  })  : _broker = broker,
        _isReachable = reachabilityChecker ?? _defaultReachabilityCheck;

  /// Get current state for all tools.
  Map<AiWorkspaceTool, ToolState> get toolStates =>
      Map.unmodifiable(_toolStates);

  /// Get state for a specific tool.
  ToolState? getState(AiWorkspaceTool tool) => _toolStates[tool];

  // -----------------------------------------------------------------------
  // Distro management
  // -----------------------------------------------------------------------

  /// Ensure the dedicated Ubuntu distro exists and is ready for use.
  /// If [forUninstall] is true, the distro must exist — do not attempt to create it.
  Future<void> ensureDistro({bool forUninstall = false}) async {
    if (_distroReady) return;

    // Check if distro already exists
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

    // During uninstall, do not attempt to create the distro — fail fast.
    if (forUninstall) {
      throw Exception(
          'AI workspace distro is not installed. Cannot uninstall.');
    }

    // Distro doesn't exist — try to install Ubuntu and rename, or import
    await _createUbuntuDistro();
  }

  /// Create the dedicated distro by installing a fresh Ubuntu instance
  /// registered under [kAiWorkspaceDistro]. This is intentionally separate
  /// from any pre-existing "Ubuntu" distro the user may already have — tools
  /// installed there before this feature existed are NOT visible here.
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

    // Installation genuinely failed — do not silently mark ready, or every
    // subsequent command will fail against a distro that doesn't exist.
    throw Exception(
        'Failed to create the AI workspace distro: ${installResult.stderr}');
  }

  /// Build WSL command arguments targeting the dedicated distro.
  ///
  /// Runs as root: this distro is automation-only (no interactive login), and
  /// apt/docker setup requires root regardless.
  List<String> _wslArgs(String shellCommand) {
    return ['-d', kAiWorkspaceDistro, '-u', 'root', 'bash', '-c', shellCommand];
  }

  /// Install (if needed) and start the Docker daemon inside the dedicated
  /// distro. The distro is a bare Ubuntu image — docker.io is not
  /// preinstalled, so Docker-backed tools (e.g. Open WebUI) need this before
  /// their first use.
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

  /// Whether [stderr] indicates the dedicated distro is missing.
  ///
  /// wsl.exe localizes its error text (e.g. German instead of English), so
  /// matching on phrases like "not found" is unreliable. The WSL error code
  /// (e.g. "WSL_E_DISTRO_NOT_FOUND") is not translated and is stable across
  /// locales and wsl.exe versions.
  static bool _indicatesMissingDistro(String stderr) {
    final lower = stderr.toLowerCase();
    return lower.contains('wsl_e_distro_not_found') ||
        lower.contains('not found') ||
        lower.contains(kAiWorkspaceDistro.toLowerCase());
  }

  // -----------------------------------------------------------------------
  // Initialization
  // -----------------------------------------------------------------------

  // -----------------------------------------------------------------------
  // Persisted status cache
  //
  // Remembers each tool's last *confirmed* status/install path across app
  // restarts (SharedPreferences), so seedToolStates() can show a real
  // answer immediately instead of a blank slate while the background check
  // runs — the whole point being that after the first successful check
  // ever, the user usually shouldn't see a checking spinner again. Only
  // ever written from a genuinely confirmed result (a successful WSL
  // response, including an explicit "distro not found" — never from a
  // broker exception or generic command failure), so a transient hiccup
  // can't clobber good cached data with a wrong guess. It's still just a
  // cache, not a guarantee — WSL may have been shut down entirely since
  // the last launch — so [ensureInitialized] always re-verifies in the
  // background regardless of what's cached; this only affects what's shown
  // while that happens.
  // -----------------------------------------------------------------------

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

  /// Create tool state entries, seeded from the persisted cache when
  /// available. Synchronous, no WSL calls — safe to call immediately on
  /// app startup or screen mount so the UI has something real to render
  /// (and a target for refreshStatus's `?.` updates) before any network/
  /// process round trip has even started.
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

  /// Initialize service and probe current status of all tools.
  ///
  /// Prefer calling [seedToolStates], [ensureDistro], and [refreshStatus]
  /// directly from a UI layer that wants to render progressively (show the
  /// page immediately, update each tool's card as its own check resolves)
  /// — this all-in-one variant blocks until every check completes, which is
  /// fine for tests/non-interactive callers but not for a page that should
  /// paint instantly.
  Future<void> init() async {
    seedToolStates();
    await ensureDistro();

    // Probe all tools concurrently rather than one at a time — each check
    // is an independent `wsl -d ...` round trip, so running them in
    // sequence pays the per-call overhead three times over for no reason.
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
      // `curl ... | sh` exits 0 even when curl fails (an empty stdin still
      // makes the piped shell "succeed"), which previously made every
      // install of a dead URL report success while installing nothing.
      // pipefail makes the pipeline's exit code reflect curl's failure too.
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
    // First stop if running.
    final state = _toolStates[tool];
    if (state != null && state.status == ToolStatus.running) {
      await stop(tool);
    }

    // During uninstall, require the distro to exist — do not attempt installation.
    try {
      await ensureDistro(forUninstall: true);
    } catch (e) {
      _toolStates[tool]?.errorMessage = e.toString();
      return false;
    }

    final config = _toolConfigs[tool]!;
    String uninstallCmd;
    if (config.defaultInstallPath.startsWith('docker://')) {
      // Docker-based tool — remove container and image.
      final imageName = config.defaultInstallPath.substring('docker://'.length);
      uninstallCmd =
          'docker rm -f $imageName && docker rmi ghcr.io/open-webui/$imageName:latest';
    } else if (tool == AiWorkspaceTool.hermesAgent) {
      // Best-effort: the installer supports multiple layouts (FHS under
      // /usr/local for root, $HOME/.hermes otherwise) and doesn't document
      // its own uninstall command, so remove every known install root.
      uninstallCmd = 'pkill -f "[h]ermes.*gateway" >/dev/null 2>&1; '
          'rm -rf "\$HOME/.hermes" /usr/local/lib/hermes-agent; hash -r';
    } else if (tool == AiWorkspaceTool.openClaw) {
      // Best-effort: remove the wrapper the installer documents, and try an
      // npm uninstall in case that was the install method (default).
      uninstallCmd = 'pkill -f "[o]penclaw" >/dev/null 2>&1; '
          'rm -f "\$HOME/.local/bin/openclaw"; '
          'npm uninstall -g openclaw >/dev/null 2>&1 || true; hash -r';
    } else {
      // Filesystem-based tool — remove install directory.
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

    // Verify the actual WSL state matches what was reported.
    await refreshStatus(tool);
    return true;
  }

  /// Refresh the current status of a tool.
  /// Build the "does this tool's install still exist" check for
  /// [installPath]. Docker-backed tools use a `docker://<container>`
  /// pseudo-path — a real container-existence check, not a filesystem one.
  static String _existsCheck(String installPath) {
    if (installPath.startsWith('docker://')) {
      final container = installPath.substring('docker://'.length);
      return 'docker inspect $container >/dev/null 2>&1 && echo exists || echo missing';
    }
    if (installPath.startsWith('cmd://')) {
      // `[ -d "~/.foo" ]` never matches: `~` doesn't expand inside double
      // quotes in bash, so a quoted-tilde path check silently reports every
      // install as missing regardless of whether it's actually there.
      // Checking PATH instead sidesteps quoting/layout assumptions entirely.
      final binary = installPath.substring('cmd://'.length);
      return 'command -v $binary >/dev/null 2>&1 && echo exists || echo missing';
    }
    return '[ -d "$installPath" ] && echo exists || echo missing';
  }

  Future<void> refreshStatus(AiWorkspaceTool tool) async {
    await ensureDistro();
    final config = _toolConfigs[tool]!;
    final isDockerBacked = config.defaultInstallPath.startsWith('docker://');

    // Docker-backed tools need the daemon actually running before `docker
    // ps`/`docker inspect` can report anything meaningful. dockerd does not
    // auto-start on distro boot, so right after a cold WSL start (e.g. app
    // just launched) it's down and both checks fail — which previously got
    // misread as "not installed" even for a tool that was genuinely
    // installed (and, since Docker still knows the container name, the next
    // install attempt then fails with "name already in use"). Starting the
    // daemon is a fast no-op when it's already running, so it's safe to
    // always prefix this in rather than trying to detect the failure mode
    // after the fact.
    final dockerPrefix =
        isDockerBacked ? 'service docker start >/dev/null 2>&1; ' : '';

    // Single round trip instead of two: run the status check, and only fall
    // through to the existence check inside the same shell invocation when
    // it isn't running. Each `wsl -d ...` call has real fixed overhead
    // (process spawn, distro handshake), so halving the invocation count
    // roughly halves this call's latency — and init() runs all three tools'
    // refreshStatus concurrently, so the real-world win compounds.
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
        // A real, successful response — safe to trust as the new cache.
        _persistConfirmedState(tool);
      } else if (_indicatesMissingDistro(result.stderr)) {
        // Distro not available means tool is not installed — also a
        // genuine confirmed signal (an explicit WSL error code), not a
        // guess, so safe to cache too.
        _toolStates[tool]?.status = ToolStatus.notInstalled;
        _toolStates[tool]?.errorMessage = null;
        _persistConfirmedState(tool);
      } else {
        // Some other command failure — not a confirmed signal about
        // install state, so leave whatever was cached before alone rather
        // than overwriting it with this error.
        _toolStates[tool]?.status = ToolStatus.error;
        _toolStates[tool]?.errorMessage = result.stderr;
      }
    } catch (e) {
      // Broker-level failure (e.g. WSL itself didn't respond) — not a
      // confirmed signal either; don't touch the cache, just reflect
      // "assume not installed" in memory for this session.
      _toolStates[tool]?.status = ToolStatus.notInstalled;
      _toolStates[tool]?.errorMessage = null;
    } finally {
      // Set regardless of outcome (including error/exception paths) — a UI
      // deciding whether to show a checking spinner cares that the check
      // was *attempted*, not just that it succeeded.
      _toolStates[tool]?.checked = true;
      _toolStates[tool]?.hasKnownStatus = true;
    }
  }

  // ---------------------------------------------------------------------
  // Background pre-fetch
  // ---------------------------------------------------------------------

  Future<void>? _initFuture;

  /// Seeds state and probes every tool's status, memoized so it only ever
  /// runs once no matter how many callers ask for it. Meant to be kicked
  /// off from app startup (fire-and-forget, before any UI needs the
  /// result) so that by the time the user actually opens the AI Workspace
  /// screen, the WSL round trips are already done — see main.dart. A
  /// caller that awaits this while it's still in flight (e.g. the screen,
  /// if the user navigates there before startup's background check
  /// finishes) just joins the same work instead of starting a duplicate.
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

  /// Get the URL for a running tool's web interface, without touching WSL.
  /// Only correct for tools whose dashboard is a fixed, static port (Open
  /// WebUI) — for anything with a [ToolConfig.dashboardCommand], use
  /// [getDashboardUrl] instead, since those need the dashboard server
  /// actually started (and may return a URL with a one-time token, not
  /// this guessed static one).
  String? getUrl(AiWorkspaceTool tool) {
    final state = _toolStates[tool];
    if (state == null || state.status != ToolStatus.running) {
      return null;
    }

    // For now, assume localhost; future: support remote host resolution.
    return 'http://localhost:${state.port}';
  }

  /// Get the URL to open a running tool's dashboard, starting the dashboard
  /// server first if the tool needs one run explicitly (see
  /// [ToolConfig.dashboardCommand]), and waiting for it to actually answer
  /// requests before returning. Returns null if the tool isn't running, no
  /// URL could be found, or nothing ever responded there — the caller can
  /// treat null uniformly as "couldn't open the dashboard" without needing
  /// to open a browser tab to a URL that isn't actually serving anything
  /// yet (Docker reporting a container "Up" — or a gateway CLI printing a
  /// link — doesn't guarantee the web server inside has finished starting;
  /// on this exact machine Open WebUI in particular has been observed
  /// taking a while past that point during first-time DB setup).
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

    // Truncate the log first so a stale URL from a previous run (e.g. an
    // already-used single-use pairing link) can't be picked up instead of
    // this run's fresh one. Poll for up to 5s rather than a single fixed
    // sleep — both tools are documented to print the link quickly, but
    // there's no guarantee of exactly how quickly.
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
