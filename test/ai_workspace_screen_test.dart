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
}
