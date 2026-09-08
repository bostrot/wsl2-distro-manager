// Pro entitlement, from one of two places depending on where the app came
// from.
//
// Windows: the app is a one-time Microsoft Store purchase and being installed
// from the Store *is* the licence, detected via MSIX package identity. The
// portable GitHub build runs unpackaged and stays free.
//
// macOS: there is no Store and no package identity, so Pro is bought on
// wslmanager.com and arrives as a licence key — typed in, or handed over by
// the browser through `wslmanager://license?key=...` after checkout. The key
// is validated once against the licence service and then cached, so the app
// keeps working offline.
//
// Neither path is protection. The repo is open source; both are a nudge.

import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:win32/win32.dart';
import 'package:wsl2distromanager/components/constants.dart';
import 'package:wsl2distromanager/components/helpers.dart';

enum LicensePlan { none, store, pro, commercial }

/// Outcome of trying to turn a licence key into an entitlement.
enum LicenseActivation {
  /// The key checked out and Pro is now unlocked.
  success,

  /// The service answered, and said no.
  invalid,

  /// The service could not be reached. The key is not rejected — a laptop on
  /// a plane must not lose Pro — but nothing is stored either.
  network,
}

/// GetCurrentPackageFullName's "this process has no package identity" code
/// (APPMODEL_ERROR_NO_PACKAGE) — not exported by package:win32.
const int _appModelErrorNoPackage = 15700;

class LicenseManager extends ChangeNotifier {
  static final LicenseManager _instance = LicenseManager._internal();
  factory LicenseManager() => _instance;
  LicenseManager._internal();

  /// How long a cached validation is trusted before the app quietly asks the
  /// service again.
  static const Duration revalidateAfter = Duration(days: 14);

  /// How long a cached validation keeps working when the service cannot be
  /// reached at all. Past this, the key has to check in again.
  static const Duration offlineGrace = Duration(days: 60);

  bool _storeLicensed = false;
  String? _licenseKey;
  String? _licenseEmail;
  int _licenseSeats = 0;
  LicensePlan _keyPlan = LicensePlan.none;
  bool _keyLicensed = false;

  /// Whether this process runs as a Store-installed (MSIX-packaged) app.
  bool get isStoreLicensed => _storeLicensed;

  /// Whether a licence key bought on the website is unlocking Pro.
  bool get isKeyLicensed => _keyLicensed;

  /// The stored key, upper-cased for display. Null when none is stored.
  String? get licenseKey => _licenseKey;

  /// Email the licence was sold to, when the service reported one.
  String? get licenseEmail => _licenseEmail;

  /// Seats on a commercial licence; 0 when not applicable.
  int get licenseSeats => _licenseSeats;

  /// Test seam — the real check asks about the test runner's process, which
  /// is never packaged. Reset to null in tearDown.
  @visibleForTesting
  static bool Function()? storeInstallCheckOverride;

  /// Test seam for the licence service. Reset to null in tearDown.
  @visibleForTesting
  static Dio? httpOverride;

  Dio get _dio => httpOverride ?? Dio();

  /// Debug builds run as Pro, so every gated feature is testable straight
  /// from `flutter run` — but never inside tests, whose assertions cover
  /// both sides of the gate. Unit runs carry FLUTTER_TEST in the
  /// environment; integration runs do not, but their binding is a test
  /// binding, which a `flutter run` never has.
  static bool get _debugBuild {
    if (!kDebugMode) return false;
    if (Platform.environment.containsKey('FLUTTER_TEST')) return false;
    try {
      if (WidgetsBinding.instance.runtimeType.toString().contains('Test')) {
        return false;
      }
    } catch (_) {
      // No binding yet — nothing test-flavoured is running.
    }
    return true;
  }

  bool get isPro => _debugBuild || _storeLicensed || _keyLicensed;

  /// Whether the destinations that are not ready to ship are shown at all:
  /// Containers, Kubernetes and Cloud.
  ///
  /// The same gate Pro rides on in a debug build, for the same reason from
  /// the other side. Each of the three drives something this app does not
  /// own — a container engine, a cluster, somebody else's servers — and each
  /// is finished enough to develop against and not finished enough to put in
  /// front of everyone. So they appear exactly where Pro is auto-granted, a
  /// `flutter run`, and nowhere else.
  ///
  /// A static, like [storeInstallCheckOverride], because the pane list and
  /// the router are read from plain functions with no instance to hand; and
  /// overridable because a test has to be able to pump both sides.
  static bool? unreleasedFeaturesOverride;

  static bool get unreleasedFeaturesVisible =>
      unreleasedFeaturesOverride ?? _debugBuild;

  LicensePlan get plan {
    if (_storeLicensed) return LicensePlan.store;
    if (_keyLicensed) return _keyPlan;
    return LicensePlan.none;
  }

  Future<void> init() async {
    _storeLicensed = _detectStoreInstall();
    _loadStoredLicense();

    // Cleanup of prefs from the retired subscription and legacy-claim
    // experiments. The current key-based licence uses the `WebLicense*`
    // names below, so nothing here touches it.
    for (final key in [
      'LicenseKey',
      'LicenseLastCheck',
      'LicenseStatus',
      'LicensePlan',
      'LicenseExpiresAt',
      'LicenseIsTrial',
      'LegacyProGranted',
      'LegacyProEmail',
      'LegacyProClaimedAt',
    ]) {
      prefs.remove(key);
    }

    notifyListeners();

    // A stored key that has not checked in for a while re-validates in the
    // background: the answer must not hold up app startup, and a revoked or
    // refunded licence should still stop working eventually.
    if (_licenseKey != null && _isStale) {
      unawaited(revalidate());
    }
  }

  /// Reads the cached entitlement written by [activate].
  void _loadStoredLicense() {
    final key = prefs.getString('WebLicenseKey')?.trim();
    if (key == null || key.isEmpty) {
      _licenseKey = null;
      _licenseEmail = null;
      _licenseSeats = 0;
      _keyPlan = LicensePlan.none;
      _keyLicensed = false;
      return;
    }

    _licenseKey = key;
    _licenseEmail = prefs.getString('WebLicenseEmail');
    _licenseSeats = prefs.getInt('WebLicenseSeats') ?? 0;
    _keyPlan = _planFromName(prefs.getString('WebLicensePlan'));

    final valid = prefs.getBool('WebLicenseValid') ?? false;
    _keyLicensed = valid && !_isBeyondGrace;
  }

  DateTime? get _checkedAt {
    final ms = prefs.getInt('WebLicenseCheckedAt');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  bool get _isStale {
    final at = _checkedAt;
    if (at == null) return true;
    return DateTime.now().difference(at) > revalidateAfter;
  }

  bool get _isBeyondGrace {
    final at = _checkedAt;
    if (at == null) return true;
    return DateTime.now().difference(at) > offlineGrace;
  }

  static LicensePlan _planFromName(String? name) {
    switch (name) {
      case 'commercial':
        return LicensePlan.commercial;
      case 'pro':
        return LicensePlan.pro;
      default:
        // An unknown plan name still came from a validated key, so treat it
        // as plain Pro rather than dropping the entitlement.
        return LicensePlan.pro;
    }
  }

  /// Validates [key] against the licence service and, if it checks out,
  /// stores it as this install's entitlement.
  Future<LicenseActivation> activate(String key) async {
    final trimmed = key.trim().toUpperCase();
    if (trimmed.isEmpty) return LicenseActivation.invalid;

    final Response<dynamic> response;
    try {
      response = await _dio.get(
        licenseValidateUrl,
        queryParameters: {'license': trimmed},
        options: Options(
          // The service answers 200 for both verdicts; anything else is a
          // transport problem, not a rejection.
          validateStatus: (status) => status != null && status < 500,
          receiveTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 15),
        ),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('Licence validation failed: $e');
      return LicenseActivation.network;
    }

    final data = response.data;
    if (data is! Map) return LicenseActivation.network;
    if (data['valid'] != true) return LicenseActivation.invalid;

    final seats = data['seats'];
    await prefs.setString('WebLicenseKey', trimmed);
    await prefs.setBool('WebLicenseValid', true);
    await prefs.setString('WebLicensePlan', '${data['plan'] ?? 'pro'}');
    await prefs.setInt(
        'WebLicenseCheckedAt', DateTime.now().millisecondsSinceEpoch);
    if (data['email'] is String) {
      await prefs.setString('WebLicenseEmail', data['email'] as String);
    }
    if (seats is int) {
      await prefs.setInt('WebLicenseSeats', seats);
    } else if (seats is String && int.tryParse(seats) != null) {
      await prefs.setInt('WebLicenseSeats', int.parse(seats));
    }

    _loadStoredLicense();
    notifyListeners();
    return LicenseActivation.success;
  }

  /// Re-checks the stored key. A rejection drops the entitlement; an
  /// unreachable service leaves it exactly as it was.
  Future<LicenseActivation> revalidate() async {
    final key = _licenseKey;
    if (key == null) return LicenseActivation.invalid;

    final result = await activate(key);
    if (result == LicenseActivation.invalid) {
      await prefs.setBool('WebLicenseValid', false);
      _loadStoredLicense();
      notifyListeners();
    }
    return result;
  }

  /// Forgets the stored licence — "sign out" for a machine being handed on.
  Future<void> clearLicense() async {
    for (final key in [
      'WebLicenseKey',
      'WebLicenseValid',
      'WebLicensePlan',
      'WebLicenseEmail',
      'WebLicenseSeats',
      'WebLicenseCheckedAt',
    ]) {
      await prefs.remove(key);
    }
    _loadStoredLicense();
    notifyListeners();
  }

  bool _detectStoreInstall() {
    final override = storeInstallCheckOverride;
    if (override != null) return override();

    // Developer escape hatch for click-throughs of the Pro-gated screens:
    // `flutter run -d windows --dart-define=WSLM_FORCE_PRO=true`. Gated behind
    // kDebugMode, so a release build always ignores it.
    if (kDebugMode && const bool.fromEnvironment('WSLM_FORCE_PRO')) {
      return true;
    }

    if (!Platform.isWindows) return false;

    try {
      return using((arena) {
        final length = arena<Uint32>();
        // Without identity: APPMODEL_ERROR_NO_PACKAGE. With it:
        // ERROR_INSUFFICIENT_BUFFER, since we pass no buffer.
        final result = GetCurrentPackageFullName(length, nullptr);
        return result != _appModelErrorNoPackage;
      });
    } catch (_) {
      // Assume unpackaged rather than crashing the gate.
      return false;
    }
  }

  String getPlanText() {
    switch (plan) {
      case LicensePlan.store:
        return 'plan-store';
      case LicensePlan.commercial:
        return 'plan-commercial';
      case LicensePlan.pro:
        return 'plan-pro';
      case LicensePlan.none:
        return 'plan-free';
    }
  }
}
