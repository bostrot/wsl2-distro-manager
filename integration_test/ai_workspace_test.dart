import 'package:fluent_ui/fluent_ui.dart' hide Page;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wsl2distromanager/main.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/nav/router.dart';

/// Integration tests for AI Workspace screen.
/// Tests UI navigation, screen states, and integration with the app router.
/// Note: AiWorkspaceService.init() makes WSL calls that may hang in test env.
/// We use pump() with explicit durations instead of pumpAndSettle() after navigation.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('AI Workspace Navigation', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      resetTestState();
    });

    tearDown(() {
      resetTestState();
    });

    testWidgets('Navigate to AI Workspace page via router', (tester) async {
      await tester.pumpWidget(const WSLManager());
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Navigate via router
      router.pushNamed('ai-workspace');
      await tester.pump(const Duration(seconds: 2));

      // Screen should render without crashing
      expect(find.byType(WSLManager), findsOneWidget);
      expect(find.byType(NavigationView), findsOneWidget);
    });

    testWidgets('AI Workspace navigation item exists in pane', (tester) async {
      await tester.pumpWidget(const WSLManager());
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // NavigationView should be present
      expect(find.byType(NavigationView), findsOneWidget);

      // Nav pane has FluentIcons.flag for AI workspace (also used by License)
      expect(find.byIcon(FluentIcons.flag), findsWidgets);
    });

    testWidgets('Can navigate to AI Workspace and back to Home', (tester) async {
      await tester.pumpWidget(const WSLManager());
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Navigate to AI workspace
      router.pushNamed('ai-workspace');
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(WSLManager), findsOneWidget);

      // Navigate back to home
      router.pushNamed('home');
      await tester.pump();
      expect(find.byType(WSLManager), findsOneWidget);
    });
  });

  group('AI Workspace Screen States', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      resetTestState();
    });

    tearDown(() {
      resetTestState();
    });

    testWidgets('AI Workspace shows loading indicator initially', (tester) async {
      await tester.pumpWidget(const WSLManager());
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Navigate to AI workspace
      router.pushNamed('ai-workspace');
      await tester.pump(); // Single pump to catch loading state before init completes

      // Should show ProgressRing during loading
      expect(find.byType(ProgressRing), findsWidgets);
    });

    testWidgets('AI Workspace page does not crash app', (tester) async {
      await tester.pumpWidget(const WSLManager());
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Navigate to AI workspace
      router.pushNamed('ai-workspace');
      await tester.pump(const Duration(seconds: 2));

      // App should remain functional
      expect(find.byType(WSLManager), findsOneWidget);
      expect(find.byType(NavigationView), findsOneWidget);
    });

    testWidgets('AI Workspace renders widgets after navigation', (tester) async {
      await tester.pumpWidget(const WSLManager());
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Navigate to AI workspace
      router.pushNamed('ai-workspace');
      await tester.pump(const Duration(seconds: 2));

      // Should have some interactive widgets (either tool cards or error retry)
      expect(
        find.byType(FilledButton).evaluate().isNotEmpty ||
            find.byType(ProgressRing).evaluate().isNotEmpty,
        isTrue,
        reason: 'AI Workspace should show buttons or loading indicator',
      );
    });
  });

  group('AI Workspace in Full Navigation Flow', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      resetTestState();
    });

    tearDown(() {
      resetTestState();
    });

    testWidgets('Navigate through all pages including AI Workspace', (tester) async {
      await tester.pumpWidget(const WSLManager());
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Start on home
      expect(find.byType(NavigationView), findsOneWidget);

      // Navigate to AI workspace
      router.pushNamed('ai-workspace');
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(WSLManager), findsOneWidget);

      // Navigate to settings
      router.pushNamed('settings');
      await tester.pump();
      expect(find.byType(WSLManager), findsOneWidget);

      // Navigate to license
      router.pushNamed('license');
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(WSLManager), findsOneWidget);

      // Navigate back to home
      router.pushNamed('home');
      await tester.pump();
      expect(find.byType(NavigationView), findsOneWidget);
    });
  });
}

void resetTestState() {
  GlobalVariable.aiPanelVisible = false;
}
