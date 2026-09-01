import '../apple/apple_vm_api.dart';
import '../execution/broker.dart';
import '../execution/models.dart';
import '../vm/vm_platform.dart';
import '../wsl_args.dart';

/// Where the AI Workspace runs its tools.
///
/// On Windows that is a dedicated WSL distro driven by `wsl.exe`; on macOS a
/// dedicated Linux VM driven over SSH by the `vmctl` helper. The service
/// builds every in-environment command through this, so the tool scripts
/// themselves stay backend-agnostic.
abstract class WorkspaceRuntime {
  /// Human-readable name of the environment, for status messages.
  String get target;

  /// One-shot root command carrying [shellCommand] as a single `sh -c`
  /// argument.
  ExecutionRequest script(String shellCommand, {Duration? timeout});

  /// A session held open so tools survive between one-shot calls. Null when
  /// the environment keeps services alive on its own (a VM does; WSL tears a
  /// distro down once its last session exits).
  ExecutionRequest? keepAlive();

  /// Whether the environment is already provisioned.
  Future<bool> exists(ExecutionBroker broker);

  /// Provision the environment, or throw with guidance when it cannot be
  /// created automatically.
  Future<void> provision(ExecutionBroker broker,
      {required void Function(String key) notify});
}

/// Picks the runtime for the active backend. Replaced by tests.
WorkspaceRuntime Function() workspaceRuntimeBuilder =
    defaultWorkspaceRuntime;

WorkspaceRuntime defaultWorkspaceRuntime() {
  final backend = vmBackend();
  if (backend is AppleVmApi) {
    return AppleWorkspaceRuntime(backend);
  }
  return WslWorkspaceRuntime();
}

/// The dedicated WSL distro the workspace has always used.
class WslWorkspaceRuntime implements WorkspaceRuntime {
  static const String distro = 'ai-workspace';

  @override
  String get target => distro;

  @override
  ExecutionRequest script(String shellCommand, {Duration? timeout}) =>
      ExecutionRequest(
        command: 'wsl',
        arguments: wslShellArgs(distro, shellCommand, user: 'root'),
        timeout: timeout ?? const Duration(minutes: 5),
      );

  @override
  ExecutionRequest? keepAlive() => ExecutionRequest(
        command: 'wsl',
        arguments: ['-d', distro, '-u', 'root', 'sleep', 'infinity'],
      );

  @override
  Future<bool> exists(ExecutionBroker broker) async {
    final result = await broker.run(ExecutionRequest(
      command: 'wsl',
      arguments: ['--list', '--quiet'],
      timeout: const Duration(seconds: 10),
    ));
    if (!result.isSuccess) return false;
    return result.stdout
        .split('\n')
        .map((s) => s.trim())
        .contains(distro);
  }

  @override
  Future<void> provision(ExecutionBroker broker,
      {required void Function(String key) notify}) async {
    notify('ai-workspace-preparing-text');
    final install = await broker.run(ExecutionRequest(
      command: 'wsl',
      arguments: ['--install', 'Ubuntu', '--name', distro],
      timeout: const Duration(minutes: 10),
    ));
    // `wsl --install` exits non-zero even when it registered the distro (it
    // also tries an interactive first-boot with no console here), so trust
    // the registry, not the exit code.
    if (install.isSuccess || await exists(broker)) return;
    final detail = [install.stderr, install.stdout]
        .map((s) => s.trim())
        .firstWhere((s) => s.isNotEmpty, orElse: () => 'no output from wsl');
    throw Exception('Failed to create the AI workspace distro: $detail');
  }
}

/// A dedicated Linux VM on the Apple backend, reached over SSH via `vmctl
/// exec`.
///
/// Unlike WSL, a bootable guest cannot be conjured from nothing — it needs an
/// installed, running Linux VM — so [provision] requires one named
/// [vmName] to exist and be running, and explains how to make it when it is
/// not. Once it is up, the tool scripts run in it exactly as they do in the
/// WSL distro (they assume a Debian/Ubuntu userland with apt).
class AppleWorkspaceRuntime implements WorkspaceRuntime {
  AppleWorkspaceRuntime(this._api);

  static const String vmName = 'ai-workspace';
  final AppleVmApi _api;

  @override
  String get target => vmName;

  List<String> _execArgs(String shellCommand) => [
        '--store',
        _api.storeDir,
        'exec',
        '--name',
        vmName,
        '--user',
        'root',
        '--',
        shellCommand,
      ];

  @override
  ExecutionRequest script(String shellCommand, {Duration? timeout}) =>
      ExecutionRequest(
        command: _api.helperPath(),
        arguments: _execArgs(shellCommand),
        timeout: timeout ?? const Duration(minutes: 5),
      );

  // A running VM keeps its services alive on its own — no held session
  // needed.
  @override
  ExecutionRequest? keepAlive() => null;

  @override
  Future<bool> exists(ExecutionBroker broker) async {
    try {
      final vm = await _api.vmInfo(vmName);
      return vm != null && vm.running;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> provision(ExecutionBroker broker,
      {required void Function(String key) notify}) async {
    final vm = await _api.vmInfo(vmName);
    if (vm == null) {
      throw Exception('ai-workspace-vm-missing-text');
    }
    if (!vm.running) {
      throw Exception('ai-workspace-vm-stopped-text');
    }
  }
}
