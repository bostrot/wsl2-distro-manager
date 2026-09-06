import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wsl2distromanager/api/license_manager.dart';
import 'package:wsl2distromanager/dialogs/rating_dialog.dart';
import 'package:wsl2distromanager/components/helpers.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    // The singleton's in-memory store flag survives across tests — pin the
    // package-identity check to a known value and re-init every time.
    LicenseManager.storeInstallCheckOverride = () => false;
    await LicenseManager().init();
  });

  tearDown(() {
    LicenseManager.storeInstallCheckOverride = null;
  });

  group('Store entitlement', () {
    test('no package identity means free plan', () {
      final manager = LicenseManager();

      expect(manager.isPro, false);
      expect(manager.isStoreLicensed, false);
      expect(manager.plan, LicensePlan.none);
      expect(manager.getPlanText(), 'plan-free');
    });

    // Regression guard for the ship-blocker: `_detectStoreInstall()` once
    // began with an unconditional `return true;`, granting Pro to every
    // install. With the test seam cleared this runs the real check — an
    // unpackaged test runner, and no --dart-define=WSLM_FORCE_PRO — so it
    // only passes while neither shortcut is hard-coded on.
    test('the real detection grants nothing to an unpackaged process',
        () async {
      LicenseManager.storeInstallCheckOverride = null;

      await LicenseManager().init();

      expect(LicenseManager().isPro, false);
      expect(LicenseManager().plan, LicensePlan.none);
    });

    test('package identity (Store install) grants Pro', () async {
      LicenseManager.storeInstallCheckOverride = () => true;
      await LicenseManager().init();

      final manager = LicenseManager();
      expect(manager.isPro, true);
      expect(manager.isStoreLicensed, true);
      expect(manager.plan, LicensePlan.store);
      expect(manager.getPlanText(), 'plan-store');
    });

    test('init clears leftover prefs from the retired Stripe experiment',
        () async {
      prefs.setString('LicenseKey', 'OLD-KEY');
      prefs.setString('LicenseStatus', 'active');
      prefs.setString('LicensePlan', 'monthly');

      await LicenseManager().init();

      expect(prefs.getString('LicenseKey'), isNull);
      expect(prefs.getString('LicenseStatus'), isNull);
      expect(prefs.getString('LicensePlan'), isNull);
    });
  });

  group('stale prefs', () {
    test('a leftover legacy grant no longer unlocks Pro', () async {
      prefs.setBool('LegacyProGranted', true);
      await LicenseManager().init();

      expect(LicenseManager().isPro, false);
      expect(prefs.getBool('LegacyProGranted'), isNull);
    });
  });

  group('rating prompt gate', () {
    test('a GitHub build is never asked - it cannot post a Store review',
        () async {
      LicenseManager.storeInstallCheckOverride = () => false;
      await LicenseManager().init();
      prefs.setInt('InstancesCreated', 99);

      await maybeShowRatingPrompt();

      // Nothing was recorded, because the prompt bailed before showing.
      expect(prefs.getBool('RatingPromptDone'), isNull);
      expect(prefs.getInt('RatingPromptNextAt'), isNull);
    });

    test('a Store install below the threshold is not asked yet', () async {
      LicenseManager.storeInstallCheckOverride = () => true;
      await LicenseManager().init();
      prefs.setInt('InstancesCreated', 1);

      await maybeShowRatingPrompt();

      expect(prefs.getBool('RatingPromptDone'), isNull);
    });

    test('recordInstanceCreated counts up', () {
      prefs.setInt('InstancesCreated', 2);
      recordInstanceCreated();
      expect(prefs.getInt('InstancesCreated'), 3);
    });

    test('a dismissed prompt stays dismissed', () async {
      LicenseManager.storeInstallCheckOverride = () => true;
      await LicenseManager().init();
      prefs.setBool('RatingPromptDone', true);
      prefs.setInt('InstancesCreated', 99);

      await maybeShowRatingPrompt();

      expect(prefs.getBool('RatingPromptDone'), true);
    });
  });
}
