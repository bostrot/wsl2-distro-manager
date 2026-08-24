import 'package:fluent_ui/fluent_ui.dart' hide Page;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wsl2distromanager/api/license_manager.dart';
import 'package:wsl2distromanager/main.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/nav/router.dart';

/// Regression coverage for the LicenseManager singleton lifecycle.
///
/// LicenseScreen used to wrap LicenseManager() — an app-wide singleton — in
/// a ChangeNotifierProvider(create: ...), which disposes whatever it creates
/// when the screen unmounts. Since the "created" value was the shared
/// singleton, leaving the License page once permanently broke Pro-gating
/// (AI chat, AI Workspace, etc.) everywhere else in the app for the rest of
/// the session. Fixed via ChangeNotifierProvider.value(), which does not
/// take ownership of the instance's lifecycle.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('LicenseManager singleton lifecycle', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      GlobalVariable.aiPanelVisible = false;
      GlobalVariable.testProEnabled = false;
    });

    tearDown(() {
      GlobalVariable.aiPanelVisible = false;
      GlobalVariable.testProEnabled = false;
    });

    testWidgets('Navigating to License and back does not crash the app',
        (tester) async {
      await tester.pumpWidget(const WSLManager());
      await tester.pumpAndSettle(const Duration(seconds: 3));

      router.pushNamed('license');
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(WSLManager), findsOneWidget);

      router.pushNamed('home');
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(WSLManager), findsOneWidget);

      // No exceptions should have been recorded during teardown of the
      // license screen's provider.
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'LicenseManager remains usable after leaving the License screen',
        (tester) async {
      await tester.pumpWidget(const WSLManager());
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Visit License, then leave it — this used to dispose() the shared
      // singleton.
      router.pushNamed('license');
      await tester.pump(const Duration(seconds: 1));
      router.pushNamed('home');
      await tester.pump(const Duration(seconds: 1));

      // The singleton must still be a live, listenable ChangeNotifier —
      // calling a method that notifies listeners must not throw.
      expect(() => LicenseManager().claimLegacyPro('still-alive@example.com'),
          returnsNormally);
      await tester.pump();

      // A second screen that depends on LicenseManager (AI Workspace's
      // paywall) must still be able to read it without crashing.
      router.pushNamed('ai-workspace');
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(WSLManager), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Legacy Pro thank-you claim', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      GlobalVariable.aiPanelVisible = false;
      GlobalVariable.testProEnabled = false;
    });

    tearDown(() {
      GlobalVariable.aiPanelVisible = false;
      GlobalVariable.testProEnabled = false;
    });

    testWidgets('claim card is visible with an email field and claim button',
        (tester) async {
      await tester.pumpWidget(const WSLManager());
      await tester.pumpAndSettle(const Duration(seconds: 3));

      router.pushNamed('license');
      await tester.pump(const Duration(seconds: 1));

      expect(find.byKey(const ValueKey('test-legacy-email-input')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('test-legacy-claim-button')),
          findsOneWidget);
    });

    testWidgets(
        'entering a valid email and claiming grants Pro and shows the confirmation card',
        (tester) async {
      await tester.pumpWidget(const WSLManager());
      await tester.pumpAndSettle(const Duration(seconds: 3));

      router.pushNamed('license');
      await tester.pump(const Duration(seconds: 1));

      await tester.enterText(
          find.byKey(const ValueKey('test-legacy-email-input')),
          'supporter@example.com');
      await tester.tap(find.byKey(const ValueKey('test-legacy-claim-button')),
          warnIfMissed: false);
      await tester.pump();
      await tester.pump();

      expect(LicenseManager().hasLegacyPro, true);
      expect(LicenseManager().isPro, true);

      // The claim form is replaced by the "you already have it" card —
      // there's nothing left to claim.
      expect(find.byKey(const ValueKey('test-legacy-email-input')),
          findsNothing);
    });

    testWidgets('an invalid email is rejected without granting anything',
        (tester) async {
      await tester.pumpWidget(const WSLManager());
      await tester.pumpAndSettle(const Duration(seconds: 3));

      router.pushNamed('license');
      await tester.pump(const Duration(seconds: 1));

      await tester.enterText(
          find.byKey(const ValueKey('test-legacy-email-input')),
          'not-an-email');
      await tester.tap(find.byKey(const ValueKey('test-legacy-claim-button')),
          warnIfMissed: false);
      await tester.pump();

      expect(LicenseManager().hasLegacyPro, false);
      // The form should still be there — nothing was granted.
      expect(find.byKey(const ValueKey('test-legacy-email-input')),
          findsOneWidget);
    });
  });
}
