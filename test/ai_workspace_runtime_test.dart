import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart' show InfoBarSeverity;
import 'package:wsl2distromanager/api/ai_workspace/runtime.dart';
import 'package:wsl2distromanager/api/apple/vm_image_catalog.dart';
import 'package:wsl2distromanager/api/cancellation.dart';
import 'package:wsl2distromanager/api/apple/apple_vm_api.dart';
import 'package:wsl2distromanager/api/execution/broker.dart';
import 'package:wsl2distromanager/api/vm/vm_platform.dart';
import 'package:wsl2distromanager/api/wsl.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/components/notify.dart';

import 'apple_vm_api_test.dart' show FakeVmctlShell;
import 'mocks.dart';

/// The AI Workspace runs its tools in a WSL distro on Windows and a Linux VM
/// on macOS; the runtime is what keeps the tool scripts backend-agnostic.
/// A catalog whose download is a fixed local file — no network.
class _FixedDownloadCatalog implements VmImageCatalog {
  _FixedDownloadCatalog(this.path);
  final String path;
  int downloads = 0;

  @override
  Future<String> download(VmIsoCatalogEntry entry,
      {void Function(int, int)? onProgress,
      CancelSignal? cancelSignal}) async {
    downloads++;
    return path;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    Notify();
    Notify.message = (msg,
        {duration,
        severity = InfoBarSeverity.info,
        loading = false,
        useWidget = false,
        leadingIcon = true,
        dynamic widget}) {};
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  tearDown(() {
    vmBackendBuilder = defaultVmBackendBuilder;
    workspaceRuntimeBuilder = defaultWorkspaceRuntime;
  });

  group('runtime selection', () {
    test('the WSL backend gets the WSL runtime', () {
      vmBackendBuilder = () => WSLApi(shell: MockShell());
      expect(defaultWorkspaceRuntime(), isA<WslWorkspaceRuntime>());
    });

    test('the Apple backend gets the VM runtime', () {
      vmBackendBuilder = () => AppleVmApi(
          shell: FakeVmctlShell(),
          helperPathOverride: '/fake/vmctl',
          storeDirOverride: '/tmp/rt-test');
      expect(defaultWorkspaceRuntime(), isA<AppleWorkspaceRuntime>());
    });
  });

  group('WSL runtime', () {
    final runtime = WslWorkspaceRuntime();

    test('scripts run as root in the dedicated distro via wsl.exe', () {
      final req = runtime.script('echo hi');
      expect(req.command, 'wsl');
      expect(req.arguments, containsAll([WslWorkspaceRuntime.distro, 'root']));
      // The single-argument shell payload survives (--exec, no re-parse).
      expect(req.arguments.join(' '), contains('echo hi'));
    });

    test('a distro keeps no services alive on its own, so it holds a session',
        () {
      expect(runtime.keepAlive(), isNotNull);
    });
  });

  group('Apple runtime', () {
    AppleWorkspaceRuntime buildRuntime(FakeVmctlShell shell) =>
        AppleWorkspaceRuntime(AppleVmApi(
            shell: shell,
            helperPathOverride: '/fake/vmctl',
            storeDirOverride: '/tmp/rt-test'));

    test('scripts run through vmctl exec against the workspace VM', () {
      final runtime = buildRuntime(FakeVmctlShell());
      final req = runtime.script('echo hi');
      expect(req.command, '/fake/vmctl');
      expect(
          req.arguments,
          containsAllInOrder(
              ['exec', '--name', AppleWorkspaceRuntime.vmName]));
      // The command is one argument past `--`, never re-split.
      final sep = req.arguments.indexOf('--');
      expect(req.arguments.sublist(sep + 1), ['echo hi']);
    });

    test('a running VM keeps its own services, so no held session', () {
      expect(buildRuntime(FakeVmctlShell()).keepAlive(), isNull);
    });

    test('exists is true only for a running workspace VM', () async {
      final shell = FakeVmctlShell();
      final broker = ExecutionBroker(shell: MockShell());
      shell.responses['list'] = '{"vms":[]}';
      expect(await buildRuntime(shell).exists(broker), isFalse);

      shell.responses['list'] =
          '{"vms":[{"name":"ai-workspace","state":"stopped"}]}';
      expect(await buildRuntime(shell).exists(broker), isFalse);

      shell.responses['list'] =
          '{"vms":[{"name":"ai-workspace","state":"running"}]}';
      expect(await buildRuntime(shell).exists(broker), isTrue);
    });

    test('guided setUp on a missing VM downloads, creates, boots and waits',
        () async {
      final shell = FakeVmctlShell();
      final broker = ExecutionBroker(shell: shell);
      final runtime = buildRuntime(shell)..setUpRetryDelay = Duration.zero;
      final dir = Directory.systemTemp.createTempSync('ws-setup-test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final image = File('${dir.path}/debian.raw')..writeAsBytesSync([1]);
      final catalog = _FixedDownloadCatalog(image.path);
      vmImageCatalogBuilder = () => catalog;
      addTearDown(() => vmImageCatalogBuilder = () => VmImageCatalog());

      shell.responseQueue['list'] = [
        '{"vms":[]}',
        '{"vms":[{"name":"ai-workspace","state":"stopped"}]}',
      ];
      shell.responses['list'] =
          '{"vms":[{"name":"ai-workspace","state":"running"}]}';
      shell.responses['exec'] = 'ok';

      await runtime.setUp(broker, notify: (_) {});

      expect(catalog.downloads, 1);
      final create = shell.calls.firstWhere((c) => c.contains('create'));
      expect(create, contains('--image'));
      expect(create[create.indexOf('--image') + 1], image.path);
      expect(shell.calls.any((c) => c.contains('start')), isTrue);
      expect(shell.calls.any((c) => c.contains('exec')), isTrue,
          reason: 'setup must verify the guest answers over SSH');
    });

    test('guided setUp on a stopped VM only boots it', () async {
      final shell = FakeVmctlShell();
      final broker = ExecutionBroker(shell: shell);
      final runtime = buildRuntime(shell)..setUpRetryDelay = Duration.zero;
      shell.responseQueue['list'] = [
        '{"vms":[{"name":"ai-workspace","state":"stopped"}]}',
      ];
      shell.responses['list'] =
          '{"vms":[{"name":"ai-workspace","state":"running"}]}';
      shell.responses['exec'] = 'ok';

      await runtime.setUp(broker, notify: (_) {});

      expect(shell.calls.any((c) => c.contains('create')), isFalse);
      expect(shell.calls.any((c) => c.contains('start')), isTrue);
    });

    test('a guest that never answers is a clear error, not a hang', () async {
      final shell = FakeVmctlShell();
      final broker = ExecutionBroker(shell: shell);
      final runtime = buildRuntime(shell)..setUpRetryDelay = Duration.zero;
      shell.responses['list'] =
          '{"vms":[{"name":"ai-workspace","state":"running"}]}';
      shell.exitCodes['exec'] = 255;

      await expectLater(
          runtime.setUp(broker, notify: (_) {}),
          throwsA(predicate((e) =>
              e.toString().contains('ai-workspace-vm-unreachable-text'))));
    });

    test('provision explains a missing or stopped VM instead of conjuring one',
        () async {
      final shell = FakeVmctlShell();
      final broker = ExecutionBroker(shell: MockShell());
      void noop(String key) {}

      shell.responses['list'] = '{"vms":[]}';
      await expectLater(
          buildRuntime(shell).provision(broker, notify: noop),
          throwsA(predicate(
              (e) => e.toString().contains('ai-workspace-vm-missing-text'))));

      shell.responses['list'] =
          '{"vms":[{"name":"ai-workspace","state":"stopped"}]}';
      await expectLater(
          buildRuntime(shell).provision(broker, notify: noop),
          throwsA(predicate(
              (e) => e.toString().contains('ai-workspace-vm-stopped-text'))));
    });
  });
}
