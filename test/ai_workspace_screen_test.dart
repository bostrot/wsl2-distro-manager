import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wsl2distromanager/api/ai_workspace/service.dart';
import 'package:wsl2distromanager/api/execution/broker.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/components/notify.dart';
import 'package:wsl2distromanager/screens/ai_workspace_screen.dart';

import 'mocks.dart';

/// The real window is 1280 wide. At the 800x600 test default the card's action
/// row overflows — and without a localization delegate the labels render as
/// raw i18n keys, which are longer still — so every card throws a layout error
/// before a single assertion runs.
const Size _kSurface = Size(1400, 1000);

/// Mounts the page with [service] behind the Provider it reads in initState.
Widget _page(AiWorkspaceService service) {
  return Provider<AiWorkspaceService>.value(
    value: service,
    child: const FluentApp(home: ScaffoldPage(content: AiWorkspacePage())),
  );
}

void main() {
  late TestShell testShell;
  late AiWorkspaceService service;

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
    // The page skips every WSL call for non-Pro users, so nothing would poll.
    GlobalVariable.testProEnabled = true;
    testShell = TestShell();
    service = AiWorkspaceService(
      broker: ExecutionBroker(shell: testShell),
      reachabilityChecker: (_) async => true,
    );
  });

  tearDown(() {
    GlobalVariable.testProEnabled = false;
    testShell.reset();
  });

  // A container that is still migrating answers `starting`, and nothing else
  // on this page re-probes a tool once it has been checked — `_initService`
  // skips anything already `checked`, and the only other timer watches
  // installs. Without a poll the card sits on "Starting up..." with Start,
  // Stop and the dashboard all disabled forever. Measured against a real
  // Open WebUI container: `docker inspect` said `healthy` while the card
  // still read "Startet...".
  testWidgets('a tool left in `starting` is re-probed until it settles',
      (tester) async {
    await tester.binding.setSurfaceSize(_kSurface);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    testShell.stdoutData = 'ai-workspace';
    await service.ensureDistro();
    service.seedToolStates();
    for (final tool in AiWorkspaceTool.values) {
      final state = service.getState(tool)!;
      state.status = ToolStatus.stopped;
      // What a completed probe leaves behind: without both flags the page
      // either re-probes over the seeded state or spins on "checking" forever.
      state.checked = true;
      state.hasKnownStatus = true;
    }
    service.getState(AiWorkspaceTool.openWebUi)!.status = ToolStatus.starting;

    await tester.pumpWidget(_page(service));
    await tester.pump(const Duration(seconds: 1));

    // The migration window: the gate keeps answering `starting`.
    expect(service.getState(AiWorkspaceTool.openWebUi)?.status,
        ToolStatus.starting);

    // Migrations finish; the very next poll has to pick that up on its own,
    // with no user interaction in between.
    testShell.stdoutData = 'running';
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();

    expect(service.getState(AiWorkspaceTool.openWebUi)?.status,
        ToolStatus.running);
  });

  // The poll must not outlive what it is waiting for, or the page keeps
  // shelling out to WSL every ten seconds for the rest of the session.
  testWidgets('the poll stops once no tool is starting', (tester) async {
    await tester.binding.setSurfaceSize(_kSurface);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    testShell.stdoutData = 'ai-workspace';
    await service.ensureDistro();
    service.seedToolStates();
    for (final tool in AiWorkspaceTool.values) {
      final state = service.getState(tool)!;
      state.status = ToolStatus.stopped;
      // What a completed probe leaves behind: without both flags the page
      // either re-probes over the seeded state or spins on "checking" forever.
      state.checked = true;
      state.hasKnownStatus = true;
    }
    service.getState(AiWorkspaceTool.openWebUi)!.status = ToolStatus.starting;

    await tester.pumpWidget(_page(service));
    await tester.pump(const Duration(seconds: 1));

    testShell.stdoutData = 'running';
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();

    final settled = testShell.allCommands.length;
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();

    expect(testShell.allCommands.length, settled);
  });

  // A tool that is simply stopped must not start a timer at all.
  testWidgets('no poll runs when nothing is starting', (tester) async {
    await tester.binding.setSurfaceSize(_kSurface);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    testShell.stdoutData = 'ai-workspace';
    await service.ensureDistro();
    service.seedToolStates();
    for (final tool in AiWorkspaceTool.values) {
      final state = service.getState(tool)!;
      state.status = ToolStatus.stopped;
      state.checked = true;
      state.hasKnownStatus = true;
    }

    await tester.pumpWidget(_page(service));
    await tester.pump(const Duration(seconds: 1));

    final settled = testShell.allCommands.length;
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();

    expect(testShell.allCommands.length, settled);
  });

  /// Puts every tool in a settled, known state so the page renders cards
  /// straight away instead of spinning on "checking".
  Future<void> seedSettled(ToolStatus status) async {
    testShell.stdoutData = 'ai-workspace';
    await service.ensureDistro();
    service.seedToolStates();
    for (final tool in AiWorkspaceTool.values) {
      final state = service.getState(tool)!;
      state.status = status;
      state.checked = true;
      state.hasKnownStatus = true;
    }
  }

  /// Runs the install of [tool] to completion, then gives the progress ticker a
  /// frame to land its own setState on.
  ///
  /// `pumpAndSettle` is unusable on this page: a status probe can land a tool
  /// back on `starting`, and that poll schedules a frame every ten seconds
  /// for as long as it runs, so nothing ever settles.
  ///
  /// The wait runs under [WidgetTester.runAsync] because cancelling a
  /// subscription of a closed StreamController never completes on the fake
  /// clock, and the streamed install cancels both of the child's pipes before
  /// it returns — on the fake clock the install simply never ends.
  Future<void> pumpInstallToEnd(
      WidgetTester tester, AiWorkspaceTool tool) async {
    await tester.runAsync(() async {
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (service.isInstalling(tool) && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    expect(service.isInstalling(tool), false,
        reason: 'the install never finished');
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
  }

  // A Hermes install runs for minutes (measured: 482s cold). Without the
  // streamed line under the card the user watches a bare spinner, and a
  // wedged installer looks exactly like a working one.
  testWidgets('the card shows installer output while the install runs',
      (tester) async {
    await tester.binding.setSurfaceSize(_kSurface);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await seedSettled(ToolStatus.notInstalled);

    final child = ControlledProcess();
    testShell.processFactory = () => child;

    await tester.pumpWidget(_page(service));
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.byKey(const ValueKey('test-ai-install-hermesAgent')));
    await tester.pump();
    // Two frames: one for the button press, one for the child to be spawned
    // and its pipes listened to before anything is written to them.
    await tester.pump(const Duration(milliseconds: 100));

    // Nothing printed yet: the placeholder holds the region open so it does
    // not pop into existence on the first line.
    expect(find.byKey(const ValueKey('test-ai-install-progress-hermesAgent')),
        findsOneWidget);

    child.emit('Cloning hermes-agent...\n');
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('Cloning hermes-agent'), findsOneWidget);

    // The line has to keep moving with no user interaction in between — the
    // page repaints on its own tick, not on a button press.
    child.emit('Installing node dependencies...\n');
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('Cloning hermes-agent'), findsNothing);
    expect(find.textContaining('Installing node dependencies'), findsOneWidget);

    child.exit(0);
    await pumpInstallToEnd(tester, AiWorkspaceTool.hermesAgent);

    // Finished: the progress region is gone and the card carries the status.
    expect(find.byKey(const ValueKey('test-ai-install-progress-hermesAgent')),
        findsNothing);
  });

  // Navigating away disposes this page; the install keeps running in the
  // service. A fresh page has to re-attach to it, progress line and all.
  testWidgets('a fresh page re-attaches to an install already in flight',
      (tester) async {
    await tester.binding.setSurfaceSize(_kSurface);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await seedSettled(ToolStatus.notInstalled);

    final child = ControlledProcess();
    testShell.processFactory = () => child;

    // Started with no page mounted at all — the service owns it.
    final install = service.install(AiWorkspaceTool.hermesAgent);
    // Let the child be spawned and its pipes listened to before anything is
    // written to them.
    await tester.pump(const Duration(milliseconds: 100));
    child.emit('Downloading Chromium 184.3 MiB\n');
    await tester.pump(const Duration(milliseconds: 100));

    await tester.pumpWidget(_page(service));
    await tester.pump(const Duration(seconds: 1));

    expect(find.textContaining('Downloading Chromium'), findsOneWidget);
    // A probe mid-install would report the tool missing and cache that over a
    // download that is still running.
    expect(service.getState(AiWorkspaceTool.hermesAgent)?.status,
        ToolStatus.notInstalled);

    child.exit(0);
    await pumpInstallToEnd(tester, AiWorkspaceTool.hermesAgent);
    expect(await tester.runAsync(() => install), true);
    expect(find.byKey(const ValueKey('test-ai-install-progress-hermesAgent')),
        findsNothing);
  });

  // A killed shell writes nothing of its own to stderr, so the last line the
  // installer managed to print is the only clue the user has about where it
  // got to. The service keeps it; the card has to keep showing it.
  testWidgets('a failed install keeps its last output on the card',
      (tester) async {
    await tester.binding.setSurfaceSize(_kSurface);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await seedSettled(ToolStatus.notInstalled);

    final child = ControlledProcess();
    testShell.processFactory = () => child;

    await tester.pumpWidget(_page(service));
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.byKey(const ValueKey('test-ai-install-hermesAgent')));
    await tester.pump();
    // Two frames: one for the button press, one for the child to be spawned
    // and its pipes listened to before anything is written to them.
    await tester.pump(const Duration(milliseconds: 100));

    child.emit('npm install --silent\n');
    await tester.pump(const Duration(seconds: 1));
    child.exit(1);
    await pumpInstallToEnd(tester, AiWorkspaceTool.hermesAgent);

    expect(service.getState(AiWorkspaceTool.hermesAgent)?.status,
        ToolStatus.error);
    expect(service.installProgress(AiWorkspaceTool.hermesAgent),
        'npm install --silent');
    expect(
        find.byKey(const ValueKey('test-ai-install-last-output-hermesAgent')),
        findsOneWidget);
  });
}
