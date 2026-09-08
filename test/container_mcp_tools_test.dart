import 'package:fluent_ui/fluent_ui.dart' show InfoBarSeverity;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wsl2distromanager/api/containers/container_service.dart';
import 'package:wsl2distromanager/api/license_manager.dart';
import 'package:wsl2distromanager/api/mcp/wsl_mcp_tools.dart';
import 'package:wsl2distromanager/api/mcp/wsl_terminal_manager.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/components/notify.dart';

import 'container_service_test.dart' show psLine;
import 'fake_container_shell.dart';
import 'vm_backend_test.dart' show FakeBackend;

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

  late FakeContainerShell shell;
  late Map<String, Future<String> Function(Map<String, dynamic>)> handlers;
  late List<String> names;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    // The family rides behind the same gate the Containers screen does; these
    // tests are about the tools themselves, so open it.
    LicenseManager.unreleasedFeaturesOverride = true;
    shell = FakeContainerShell();
    final backend = FakeBackend();
    final tools = buildWslMcpTools(
      backend,
      WslTerminalManager(wslApi: backend),
      containerService: ContainerService(shell: shell),
    );
    handlers = {for (final t in tools) t.name: t.handler};
    names = tools.map((t) => t.name).toList();
  });

  tearDown(() => LicenseManager.unreleasedFeaturesOverride = null);

  test('the family is not registered while Containers is unreleased', () {
    // An MCP client is as much a shipped surface as the nav pane, so a
    // hidden screen must not leave its tools reachable from Claude Desktop.
    LicenseManager.unreleasedFeaturesOverride = false;
    final backend = FakeBackend();
    final hidden = buildWslMcpTools(backend, WslTerminalManager(wslApi: backend))
        .map((t) => t.name);
    expect(hidden.where((n) => n.startsWith('container_')), isEmpty);
    // The rest of the surface is untouched.
    expect(hidden, contains('wsl_list_distros'));
  });

  test('the container family is registered on every backend', () {
    expect(
        names,
        containsAll([
          'container_list',
          'container_engines',
          'container_start',
          'container_stop',
          'container_restart',
          'container_remove',
          'container_logs',
          'container_exec',
          'container_inspect',
        ]));
  });

  test('container_list reports every engine and its containers', () async {
    shell.responses['docker ps'] =
        psLine('a1', 'web', 'nginx:latest', 'running', 'Up 2 hours', '80/tcp');
    shell.responses['podman ps'] = psLine('b2', 'db', 'postgres', 'exited');

    final out = await handlers['container_list']!({});
    expect(out, contains('[docker] web (running)'));
    expect(out, contains('[podman] db (exited)'));
  });

  test('container_list says so when the host has no containers', () async {
    final out = await handlers['container_list']!({});
    expect(out, contains('No containers'));
  });

  test('container_list restricted to one engine only asks that one', () async {
    shell.responses['docker ps'] = psLine('a1', 'web', 'nginx', 'running');
    await handlers['container_list']!({'engine': 'docker'});
    expect(shell.calls.where((c) => c.first == 'podman' && c.contains('ps')),
        isEmpty);
  });

  test('an unknown engine name is refused', () async {
    expect(() => handlers['container_list']!({'engine': 'containerd'}),
        throwsArgumentError);
  });

  test('container_engines lists what is installed and which one is active',
      () async {
    shell.missing.add('podman');
    final out = await handlers['container_engines']!({});
    expect(out, contains('Docker'));
    expect(out, contains('active'));
    expect(out, isNot(contains('Podman')));
  });

  test('every tool explains itself when no engine is installed', () async {
    shell.missing.addAll(['docker', 'podman']);
    for (final tool in ['container_list', 'container_engines']) {
      final out = await handlers[tool]!({});
      expect(out, contains('No container engine found'), reason: tool);
    }
    expect(() => handlers['container_stop']!({'container': 'web'}),
        throwsArgumentError);
  });

  test('container_start and container_stop drive the engine', () async {
    expect(await handlers['container_start']!({'container': 'web'}),
        contains('Started web'));
    expect(shell.calls.last, ['docker', 'start', 'web']);

    expect(await handlers['container_stop']!({'container': 'web'}),
        contains('Stopped web'));
    expect(shell.calls.last, ['docker', 'stop', 'web']);
  });

  test('container_remove refuses without the confirm flag', () async {
    expect(() => handlers['container_remove']!({'container': 'web'}),
        throwsArgumentError);
    expect(shell.calls.where((c) => c.contains('rm')), isEmpty);

    final out = await handlers['container_remove']!(
        {'container': 'web', 'confirm': true, 'force': true});
    expect(out, contains('Removed web'));
    expect(shell.calls.last, ['docker', 'rm', '--force', 'web']);
  });

  test('container_logs defaults to a bounded tail', () async {
    shell.responses['docker logs'] = 'hello';
    final out = await handlers['container_logs']!({'container': 'web'});
    expect(out, 'hello');
    expect(shell.calls.last, ['docker', 'logs', '--tail', '200', 'web']);
  });

  test('container_exec returns the command output', () async {
    shell.responses['docker exec'] = 'root';
    final out = await handlers['container_exec']!(
        {'container': 'web', 'command': 'whoami'});
    expect(out, 'root');
  });

  test('container_exec needs both a container and a command', () async {
    expect(() => handlers['container_exec']!({'container': 'web'}),
        throwsArgumentError);
    expect(() => handlers['container_exec']!({'command': 'whoami'}),
        throwsArgumentError);
  });

  test('the pinned engine is what the tools use by default', () async {
    await prefs.setString(containerEnginePrefKey, 'podman');
    await handlers['container_start']!({'container': 'web'});
    expect(shell.calls.last, ['podman', 'start', 'web']);
  });
}
