/// Widget tests for lib/screens/containers_screen.dart — the Docker/Podman
/// surface added for bostrot/ai-tasks#57.
///
/// There is no localization delegate here, so `.i18n()` returns the key it was
/// given; asserting on `containers-text` is what proves the label goes through
/// i18n rather than being a hardcoded English string.
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wsl2distromanager/api/containers/container_service.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/components/notify.dart';
import 'package:wsl2distromanager/screens/containers_screen.dart';

import 'container_service_test.dart' show psLine;
import 'fake_container_shell.dart';

void main() {
  late FakeContainerShell shell;
  final messages = <String>[];

  setUpAll(() {
    Notify();
    Notify.message = (msg,
        {duration,
        severity = InfoBarSeverity.info,
        loading = false,
        useWidget = false,
        leadingIcon = true,
        dynamic widget}) {
      messages.add(msg.toString());
    };
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    messages.clear();
    shell = FakeContainerShell();
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(FluentApp(
      home: ScaffoldPage(
        content: ContainersPage(service: ContainerService(shell: shell)),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// Every command the shell has been handed, one string per call — argv
  /// lists compare by identity, which no assertion can use.
  List<String> ran() => shell.calls.map((call) => call.join(' ')).toList();

  /// The row's buttons live inside a collapsed Expander, so nothing under it
  /// is in the tree until the header is tapped.
  Future<void> openRow(WidgetTester tester, String name) async {
    await tester.tap(find.textContaining(name).first);
    await tester.pumpAndSettle();
  }

  testWidgets('a host without an engine gets an explanation, not an error',
      (tester) async {
    shell.missing.addAll(['docker', 'podman']);
    await pump(tester);

    expect(find.byKey(const ValueKey('test-containers-no-engine')),
        findsOneWidget);
    expect(find.text('nocontainerenginehint-text'), findsOneWidget);
  });

  testWidgets('an engine with nothing in it says so', (tester) async {
    await pump(tester);
    expect(
        find.byKey(const ValueKey('test-containers-empty')), findsOneWidget);
  });

  testWidgets("a failing engine shows the engine's own message",
      (tester) async {
    shell.exitCodes['docker ps'] = 1;
    shell.errors['docker ps'] = 'Cannot connect to the Docker daemon';
    shell.exitCodes['podman ps'] = 125;
    shell.errors['podman ps'] = 'podman machine is not running';
    await pump(tester);

    expect(
        find.byKey(const ValueKey('test-containers-error')), findsOneWidget);
    expect(find.textContaining('Cannot connect to the Docker daemon'),
        findsOneWidget);
  });

  testWidgets('containers from both engines are listed with their state',
      (tester) async {
    shell.responses['docker ps'] =
        psLine('a1', 'web', 'nginx:latest', 'running', 'Up 2 hours', '80/tcp');
    shell.responses['podman ps'] = psLine('b2', 'db', 'postgres', 'exited');
    await pump(tester);

    expect(find.textContaining('web (running-text)'), findsOneWidget);
    expect(find.textContaining('db (stopped-text)'), findsOneWidget);
    // The caption tells two same-named containers apart.
    expect(find.textContaining('nginx:latest · Docker · 80/tcp'),
        findsOneWidget);
  });

  testWidgets('the toggle stops a running container and starts a stopped one',
      (tester) async {
    shell.responses['docker ps'] =
        psLine('a1', 'web', 'nginx', 'running');
    shell.responses['podman ps'] = psLine('b2', 'db', 'postgres', 'exited');
    await pump(tester);

    await openRow(tester, 'web');
    await tester.tap(find.byKey(const ValueKey('test-container-toggle-web')));
    await tester.pumpAndSettle();
    expect(ran(), contains('docker stop web'));

    await openRow(tester, 'db');
    await tester.tap(find.byKey(const ValueKey('test-container-toggle-db')));
    await tester.pumpAndSettle();
    expect(ran(), contains('podman start db'));
  });

  testWidgets('a failed action surfaces the engine text in the status bar',
      (tester) async {
    shell.responses['docker ps'] = psLine('a1', 'web', 'nginx', 'running');
    shell.exitCodes['docker stop'] = 1;
    shell.errors['docker stop'] = 'container web is restarting';
    await pump(tester);

    await openRow(tester, 'web');
    await tester.tap(find.byKey(const ValueKey('test-container-toggle-web')));
    await tester.pumpAndSettle();

    expect(messages.join('\n'), contains('container web is restarting'));
  });

  testWidgets('deleting asks first and only then removes', (tester) async {
    shell.responses['docker ps'] = psLine('a1', 'web', 'nginx', 'running');
    await pump(tester);

    await openRow(tester, 'web');
    await tester.tap(find.byKey(const ValueKey('test-container-delete-web')));
    await tester.pumpAndSettle();

    // The confirmation is up and nothing has been removed yet.
    expect(find.text('deletecontainerbody-text'), findsOneWidget);
    expect(shell.calls.where((c) => c.contains('rm')), isEmpty);

    await tester.tap(find.text('delete-text').last);
    await tester.pumpAndSettle();
    // Running, so the engine would refuse a plain rm.
    expect(ran(), contains('docker rm --force web'));
  });

  testWidgets('logs open in a dialog', (tester) async {
    shell.responses['docker ps'] = psLine('a1', 'web', 'nginx', 'running');
    shell.responses['docker logs'] = 'listening on :80';
    await pump(tester);

    await openRow(tester, 'web');
    await tester.tap(find.byKey(const ValueKey('test-container-logs-web')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('test-container-logs-dialog')),
        findsOneWidget);
    expect(find.text('listening on :80'), findsOneWidget);
  });

  testWidgets('refresh re-probes for an engine installed since startup',
      (tester) async {
    shell.missing.addAll(['docker', 'podman']);
    await pump(tester);
    expect(find.byKey(const ValueKey('test-containers-no-engine')),
        findsOneWidget);

    shell.missing.clear();
    shell.responses['docker ps'] = psLine('a1', 'web', 'nginx', 'running');
    await tester.tap(find.byKey(const ValueKey('test-containers-refresh')));
    await tester.pumpAndSettle();

    expect(find.textContaining('web (running-text)'), findsOneWidget);
  });
}
