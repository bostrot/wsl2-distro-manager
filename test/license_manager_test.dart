import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wsl2distromanager/api/license_manager.dart';
import 'package:wsl2distromanager/api/updater.dart' show compareVersions;
import 'package:wsl2distromanager/components/constants.dart';
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
    LicenseManager.storeFreeFromOverride = null;
  });

  /// A moment safely either side of any flip these tests schedule.
  final past = DateTime.utc(2000);
  final future = DateTime.utc(2999);

  /// What a released build reports. The repo's copy says 1.0.0 until the
  /// release workflow stamps the tag in, and the grandfather rule refuses to
  /// judge a version stamp from a build that has not been stamped itself.
  final stampedVersion = '2.9.0';

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

    test('package identity (Store install) grants Pro before the flip',
        () async {
      LicenseManager.storeInstallCheckOverride = () => true;
      LicenseManager.storeFreeFromOverride =
          DateTime.now().toUtc().add(const Duration(days: 1));
      await LicenseManager().init();

      final manager = LicenseManager();
      expect(manager.isPro, true);
      expect(manager.isStoreLicensed, true);
      expect(manager.plan, LicensePlan.store);
      expect(manager.getPlanText(), 'plan-store');
    });

    test('a Store install is recorded as entitled the first time it runs',
        () async {
      // The evidence is perishable — the flip passes and the stored version
      // is overwritten on every start — so the answer is written down.
      LicenseManager.storeInstallCheckOverride = () => true;
      LicenseManager.storeFreeFromOverride =
          DateTime.now().toUtc().add(const Duration(days: 1));
      await LicenseManager().init();

      expect(prefs.getBool(storeGrandfatheredPref), true);
    });

    test('a portable build records nothing, even next to a stale flag',
        () async {
      // The flag is about a Store copy that was paid for; on an unpackaged
      // build it is not evidence of anything.
      prefs.setBool(storeGrandfatheredPref, true);
      LicenseManager.storeInstallCheckOverride = () => false;
      await LicenseManager().init();

      expect(LicenseManager().isPro, false);
      expect(LicenseManager().isStoreLicensed, false);
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

  group('when the Store listing goes free', () {
    late String realVersion;

    setUp(() {
      LicenseManager.storeInstallCheckOverride = () => true;
      realVersion = currentVersion;
      currentVersion = stampedVersion;
    });

    tearDown(() => currentVersion = realVersion);

    test('a copy running before the flip is Pro, and stays Pro afterwards',
        () async {
      LicenseManager.storeFreeFromOverride = future;
      await LicenseManager().init();
      expect(LicenseManager().isPro, true,
          reason: 'bought while it cost money');

      // The same install, some time after the listing went free. Nothing
      // about it changed except the date.
      LicenseManager.storeFreeFromOverride = past;
      prefs.setString('version', currentVersion);
      await LicenseManager().init();

      expect(LicenseManager().isPro, true);
      expect(LicenseManager().plan, LicensePlan.store);
    });

    test('a copy that only ever ran a pre-freemium build is Pro', () async {
      // It updated for the first time after the flip, so it never got to
      // record the flip passing — but a free download cannot have been
      // running 2.1.0, because free downloads did not exist then.
      LicenseManager.storeFreeFromOverride = past;
      prefs.setString('version', '2.1.0');
      await LicenseManager().init();

      expect(LicenseManager().isPro, true);
      expect(prefs.getBool(storeGrandfatheredPref), true);
    });

    test('a fresh free install is not Pro', () async {
      LicenseManager.storeFreeFromOverride = past;
      await LicenseManager().init();

      expect(LicenseManager().isPro, false);
      expect(LicenseManager().plan, LicensePlan.none);
      expect(prefs.getBool(storeGrandfatheredPref), isNull);
    });

    test('an unstamped build grandfathers nobody', () async {
      // 1.0.0 is what the repo says before the release workflow replaces it.
      // Judged against it, the second start of a fresh free install looks
      // like a copy from the paid era — so such a build declines to judge.
      currentVersion = '1.0.0';
      LicenseManager.storeFreeFromOverride = past;
      prefs.setString('version', '1.0.0');
      await LicenseManager().init();

      expect(LicenseManager().isPro, false);
    });

    test('a free install that has been updated since is still not Pro',
        () async {
      // The version it last ran is from the freemium era, so it says
      // nothing about a purchase.
      LicenseManager.storeFreeFromOverride = past;
      prefs.setString('version', storeFreemiumVersion);
      await LicenseManager().init();

      expect(LicenseManager().isPro, false);
    });

    test('a licence key still unlocks a free Store copy', () async {
      // The Store build has to be able to redeem a website purchase like
      // any other, or a buyer who installed from the Store has nowhere to
      // put their key.
      LicenseManager.storeFreeFromOverride = past;
      await LicenseManager().init();
      expect(LicenseManager().isPro, false);

      prefs.setString('WebLicenseKey', 'AAAA-BBBB');
      prefs.setBool('WebLicenseValid', true);
      prefs.setString('WebLicensePlan', 'pro');
      prefs.setInt(
          'WebLicenseCheckedAt', DateTime.now().millisecondsSinceEpoch);
      await LicenseManager().init();

      expect(LicenseManager().isPro, true);
      expect(LicenseManager().plan, LicensePlan.pro);
    });

    test('the Store is only advertised as selling Pro until the flip', () {
      LicenseManager.storeFreeFromOverride = future;
      expect(LicenseManager.storeSellsPro, true);

      LicenseManager.storeFreeFromOverride = past;
      expect(LicenseManager.storeSellsPro, false);

      // With no override the shipped constant decides, and its instant has
      // passed: no build carrying it advertises the Store as selling Pro.
      LicenseManager.storeFreeFromOverride = null;
      expect(LicenseManager.storeSellsPro, false);
    });

    test('the shipped build flips at the instant the listing goes free', () {
      // store/pricing.json says Free and the release workflow publishes it,
      // so the app has to carry a flip instant that is no later than the
      // moment that submission clears certification. One in the past is
      // the safe side: no paid-era build knows about it, and every build
      // that does arrives together with the price change.
      LicenseManager.storeFreeFromOverride = null;
      final flip = LicenseManager.storeFreeFrom;
      expect(flip, isNotNull,
          reason: 'storeFreeFromUtc is null - store/pricing.json says Free');
      expect(flip!.isUtc, true);
      expect(flip, DateTime.utc(2026, 9, 13));
      expect(flip.isBefore(DateTime.now().toUtc()), true,
          reason: 'an instant certification could overshoot would hand Pro '
              'to free downloads made before it');
    });

    test('the freemium version is newer than every paid-era release', () {
      // 2.1.0 was the last release sold in the Store. A free download can
      // never have run it, which is what the last-ran-version fallback
      // relies on.
      expect(compareVersions(storeFreemiumVersion, '2.1.0'), greaterThan(0));
    });

    test('the shipped build is new enough to judge', () {
      // The release workflow stamps currentVersion from pubspec.yaml, and
      // storeGrandfathers declines to grandfather anyone from a build older
      // than storeFreemiumVersion — so a pubspec behind the constant would
      // ship a free listing whose updated buyers all land on Free.
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final version = RegExp(r'^version:\s*([^\s#]+)', multiLine: true)
          .firstMatch(pubspec)!
          .group(1)!;
      expect(compareVersions(version, storeFreemiumVersion),
          greaterThanOrEqualTo(0),
          reason: 'pubspec.yaml says $version, '
              'storeFreemiumVersion is $storeFreemiumVersion');
    });

    test('a Store install still counts as a Store install', () async {
      // Updates and the rating prompt follow the package, not the
      // entitlement: a free Store copy is updated by the Store and can post
      // a review just as well as a paid one.
      LicenseManager.storeFreeFromOverride = past;
      await LicenseManager().init();

      expect(LicenseManager().isPro, false);
      expect(LicenseManager().isStorePackaged, true);
    });
  });

  group('parseFlipInstant', () {
    test('nothing scheduled reads as nothing scheduled', () {
      expect(parseFlipInstant(null), isNull);
      expect(parseFlipInstant(''), isNull);
      expect(parseFlipInstant('   '), isNull);
      expect(parseFlipInstant('not a date'), isNull);
    });

    test('an instant is the same instant everywhere', () {
      // Without a zone DateTime.parse reads local time, and the app would
      // flip at a different moment in every time zone while the listing
      // flips at one.
      final withZone = parseFlipInstant('2026-10-01T09:00:00Z')!;
      final withoutZone = parseFlipInstant('2026-10-01T09:00:00')!;

      expect(withZone.isUtc, true);
      expect(withoutZone.isUtc, true);
      expect(withoutZone, withZone);
      expect(withZone, DateTime.utc(2026, 10, 1, 9));
    });

    test('an offset is honoured rather than ignored', () {
      expect(parseFlipInstant('2026-10-01T11:00:00+02:00'),
          DateTime.utc(2026, 10, 1, 9));
    });
  });

  group('storeGrandfathers', () {
    late String realVersion;

    setUp(() {
      realVersion = currentVersion;
      currentVersion = stampedVersion;
    });

    tearDown(() => currentVersion = realVersion);

    bool decide({
      bool packaged = true,
      DateTime? freeFrom,
      String? lastRanVersion,
      bool alreadyGranted = false,
      DateTime? now,
    }) =>
        storeGrandfathers(
          packaged: packaged,
          now: now ?? DateTime.utc(2026, 10, 1),
          freeFrom: freeFrom,
          lastRanVersion: lastRanVersion,
          alreadyGranted: alreadyGranted,
        );

    test('an unpackaged build is never grandfathered', () {
      expect(decide(packaged: false, alreadyGranted: true), false);
      expect(decide(packaged: false, lastRanVersion: '1.0.0'), false);
    });

    test('with no flip scheduled every Store install is a paid one', () {
      expect(decide(), true);
    });

    test('the flip is the dividing line', () {
      final flip = DateTime.utc(2026, 10, 1, 9);
      final justBefore = flip.subtract(const Duration(minutes: 1));
      expect(decide(freeFrom: flip, now: justBefore), true);
      expect(decide(freeFrom: flip, now: flip), false);
    });

    test('an already granted install is never re-judged', () {
      expect(
          decide(
              freeFrom: DateTime.utc(2020),
              lastRanVersion: '9.9.9',
              alreadyGranted: true),
          true);
    });

    test('after the flip, only a pre-freemium version grandfathers', () {
      final after = DateTime.utc(2026, 11);
      final flip = DateTime.utc(2026, 10);

      expect(decide(freeFrom: flip, now: after, lastRanVersion: '2.1.0'), true);
      expect(
          decide(freeFrom: flip, now: after, lastRanVersion: '1.11.9'), true);
      expect(
          decide(
              freeFrom: flip, now: after, lastRanVersion: storeFreemiumVersion),
          false);
      expect(
          decide(freeFrom: flip, now: after, lastRanVersion: '3.0.0'), false);
      expect(decide(freeFrom: flip, now: after, lastRanVersion: null), false);
    });

    test('a build that predates the freemium release judges nobody', () {
      currentVersion = '1.0.0';

      expect(
          decide(
              freeFrom: DateTime.utc(2026, 10),
              now: DateTime.utc(2026, 11),
              lastRanVersion: '1.0.0'),
          false);
      // The sticky flag is still honoured: it was earned by an earlier,
      // properly stamped build and is not re-derived here.
      expect(
          decide(
              freeFrom: DateTime.utc(2026, 10),
              now: DateTime.utc(2026, 11),
              lastRanVersion: '1.0.0',
              alreadyGranted: true),
          true);
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
