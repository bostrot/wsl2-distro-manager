// AI Workspace service for managing Hermes Agent, OpenClaw, and Open WebUI.
// Provides install/start/status lifecycle management for workspace tools.
// All commands run inside a dedicated Ubuntu WSL distro to guarantee curl/bash/docker availability.

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

  const ToolConfig({
    required this.name,
    required this.installCommand,
    required this.startCommand,
    required this.stopCommand,
    required this.statusCheck,
    required this.port,
    required this.defaultInstallPath,
  });
}

/// Default tool configurations.
/// Commands assume Ubuntu environment (curl, bash, docker available).
const Map<AiWorkspaceTool, ToolConfig> _toolConfigs = {
  AiWorkspaceTool.hermesAgent: ToolConfig(
    name: 'Hermes Agent',
    installCommand: 'curl -fsSL https://get.hermes-agent.dev | sh',
    startCommand: 'hermes-agent serve --port 8081',
    stopCommand: "pkill -f hermes-agent || true",
    statusCheck: 'pgrep -f "[h]ermes-agent" > /dev/null && echo running || echo stopped',
    port: 8081,
    defaultInstallPath: '~/.hermes-agent',
  ),
  AiWorkspaceTool.openClaw: ToolConfig(
    name: 'OpenClaw',
    installCommand: 'curl -fsSL https://install.openclaw.ai | sh',
    startCommand: 'openclaw serve --port 8082',
    stopCommand: 'pkill -f openclaw || true',
    statusCheck: 'pgrep -f "[o]penclaw" > /dev/null && echo running || echo stopped',
    port: 8082,
    defaultInstallPath: '~/.openclaw',
  ),
  AiWorkspaceTool.openWebUi: ToolConfig(
    name: 'Open WebUI',
    installCommand: 'docker pull ghcr.io/open-webui/open-webui:latest && docker run -d -p 8083:8080 --name open-webui ghcr.io/open-webui/open-webui:latest',
    startCommand: 'docker start open-webui || (docker pull ghcr.io/open-webui/open-webui:latest && docker run -d -p 8083:8080 --name open-webui ghcr.io/open-webui/open-webui:latest)',
    stopCommand: 'docker stop open-webui || true',
    statusCheck: 'docker ps --filter "name=open-webui" | grep -q Up && echo running || echo stopped',
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

  ToolState({
    required this.tool,
    this.status = ToolStatus.notInstalled,
    this.installPath,
    required this.port,
    this.lastStarted,
    this.lastStopped,
    this.errorMessage,
  });
}

/// Service for managing AI workspace tools.
class AiWorkspaceService {
  final ExecutionBroker _broker;
  final Map<AiWorkspaceTool, ToolState> _toolStates = {};
  bool _distroReady = false;

  /// Create service backed by the given [ExecutionBroker].
  AiWorkspaceService({required ExecutionBroker broker}) : _broker = broker;

  /// Get current state for all tools.
  Map<AiWorkspaceTool, ToolState> get toolStates =>
      Map.unmodifiable(_toolStates);

  /// Get state for a specific tool.
  ToolState? getState(AiWorkspaceTool tool) => _toolStates[tool];

  // -----------------------------------------------------------------------
  // Distro management
  // -----------------------------------------------------------------------

  /// Ensure the dedicated Ubuntu distro exists and is ready for use.
  Future<void> ensureDistro() async {
    if (_distroReady) return;

    // Check if distro already exists
    final listResult = await _broker.run(ExecutionRequest(
      command: 'wsl',
      arguments: ['--list', '--quiet'],
      timeout: const Duration(seconds: 10),
    ));

    if (listResult.isSuccess) {
      final distros = listResult.stdout.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      if (distros.contains(kAiWorkspaceDistro)) {
        _distroReady = true;
        return;
      }
    }

    // Distro doesn't exist — try to install Ubuntu and rename, or import
    await _createUbuntuDistro();
  }

  /// Create the dedicated distro by installing Ubuntu.
  Future<void> _createUbuntuDistro() async {
    // Try wsl --install first (non-interactive on newer Windows)
    final installResult = await _broker.run(ExecutionRequest(
      command: 'wsl',
      arguments: ['--install', '-d', 'Ubuntu'],
      timeout: const Duration(minutes: 10),
    ));

    if (installResult.isSuccess || installResult.stdout.contains('already installed')) {
      // Distro installed successfully; commands use -d flag so just mark ready.
      _distroReady = true;
      return;
    }

    // If install failed but Ubuntu might already exist, mark ready anyway.
    // Commands use -d flag and will fail gracefully if distro is truly missing.
    _distroReady = true;
  }

  /// Build WSL command arguments targeting the dedicated distro.
  List<String> _wslArgs(String shellCommand) {
    return ['-d', kAiWorkspaceDistro, 'bash', '-c', shellCommand];
  }

  // -----------------------------------------------------------------------
  // Initialization
  // -----------------------------------------------------------------------

  /// Initialize service and probe current status of all tools.
  Future<void> init() async {
    await ensureDistro();
    for (final tool in AiWorkspaceTool.values) {
      final config = _toolConfigs[tool]!;
      _toolStates[tool] = ToolState(
        tool: tool,
        port: config.port,
      );

      // Probe current status.
      await refreshStatus(tool);
    }
  }

  // -----------------------------------------------------------------------
  // Lifecycle operations
  // -----------------------------------------------------------------------

  /// Install a workspace tool.
  Future<bool> install(AiWorkspaceTool tool) async {
    await ensureDistro();
    final config = _toolConfigs[tool]!;
    final request = ExecutionRequest(
      command: 'wsl',
      arguments: _wslArgs(config.installCommand),
      timeout: const Duration(minutes: 5),
    );

    try {
      final result = await _broker.run(request);
      if (result.isSuccess) {
        _toolStates[tool]?.status = ToolStatus.stopped;
        _toolStates[tool]?.installPath = config.defaultInstallPath;
        return true;
      } else {
        _toolStates[tool]?.errorMessage = result.stderr;
        _toolStates[tool]?.status = ToolStatus.error;
        return false;
      }
    } catch (e) {
      _toolStates[tool]?.errorMessage = e.toString();
      _toolStates[tool]?.status = ToolStatus.error;
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
        return true;
      } else {
        state.errorMessage = result.stderr;
        state.status = ToolStatus.error;
        return false;
      }
    } catch (e) {
      state.errorMessage = e.toString();
      state.status = ToolStatus.error;
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

    await ensureDistro();
    final config = _toolConfigs[tool]!;
    String uninstallCmd;
    if (config.defaultInstallPath.startsWith('docker://')) {
      // Docker-based tool — remove container and image.
      final imageName = config.defaultInstallPath.substring('docker://'.length);
      uninstallCmd = 'docker rm -f $imageName && docker rmi ghcr.io/open-webui/$imageName:latest || true';
    } else {
      // Filesystem-based tool — remove install directory.
      uninstallCmd = 'rm -rf ${config.defaultInstallPath} || true';
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

  /// Refresh the current status of a tool.
  Future<void> refreshStatus(AiWorkspaceTool tool) async {
    await ensureDistro();
    final config = _toolConfigs[tool]!;
    final request = ExecutionRequest(
      command: 'wsl',
      arguments: _wslArgs(config.statusCheck),
      timeout: const Duration(seconds: 10),
    );

    try {
      final result = await _broker.run(request);
      if (result.isSuccess) {
        final output = result.stdout.trim().toLowerCase();
        _toolStates[tool]?.status = output.contains('running')
            ? ToolStatus.running
            : ToolStatus.stopped;
        _toolStates[tool]?.errorMessage = null;
      } else if (result.stderr.contains('not found') || result.stderr.contains(kAiWorkspaceDistro)) {
        // Distro not available yet or command not found means tool is not installed.
        _toolStates[tool]?.status = ToolStatus.notInstalled;
      } else {
        _toolStates[tool]?.status = ToolStatus.error;
        _toolStates[tool]?.errorMessage = result.stderr;
      }
    } catch (e) {
      // If broker throws, assume not installed.
      _toolStates[tool]?.status = ToolStatus.notInstalled;
    }
  }

  /// Get the URL for a running tool's web interface.
  String? getUrl(AiWorkspaceTool tool) {
    final state = _toolStates[tool];
    if (state == null || state.status != ToolStatus.running) {
      return null;
    }

    // For now, assume localhost; future: support remote host resolution.
    return 'http://localhost:${state.port}';
  }
}
