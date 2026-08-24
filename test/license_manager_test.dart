import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wsl2distromanager/api/license_manager.dart';
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

  group('LicenseManager legacy Pro claim', () {
    test('claiming with a valid email grants Pro permanently', () {
      final manager = LicenseManager();

      final granted = manager.claimLegacyPro('someone@example.com');

      expect(granted, true);
      expect(manager.hasLegacyPro, true);
      expect(manager.isPro, true);
      expect(manager.plan, LicensePlan.legacy);
      expect(manager.legacyProEmail, 'someone@example.com');
    });

    test('claiming with a malformed email is rejected', () {
      final manager = LicenseManager();

      final granted = manager.claimLegacyPro('not-an-email');

      expect(granted, false);
      expect(manager.hasLegacyPro, false);
      expect(manager.isPro, false);
    });

    test('claiming with an empty email is rejected', () {
      final manager = LicenseManager();

      final granted = manager.claimLegacyPro('');

      expect(granted, false);
      expect(manager.hasLegacyPro, false);
    });

    test('trims whitespace around the email before validating', () {
      final manager = LicenseManager();

      final granted = manager.claimLegacyPro('  someone@example.com  ');

      expect(granted, true);
      expect(manager.legacyProEmail, 'someone@example.com');
    });

    test('legacy grant wins over store plan in plan reporting', () async {
      LicenseManager.storeInstallCheckOverride = () => true;
      await LicenseManager().init();
      LicenseManager().claimLegacyPro('someone@example.com');

      // Both entitlements present — legacy is reported (it predates the
      // store purchase and is the more meaningful label for the user).
      expect(LicenseManager().plan, LicensePlan.legacy);
      expect(LicenseManager().isPro, true);
    });

    test('claim window is currently open', () {
      // Sanity check on the hardcoded cutoff — this test starts failing
      // (correctly) once the window has actually closed, as a reminder to
      // reconsider the feature rather than silently letting it linger.
      expect(LicenseManager().isLegacyClaimWindowOpen, true);
    });
  });
}
