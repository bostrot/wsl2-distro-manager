// Pro entitlement. The app is a one-time Microsoft Store purchase — no
// subscription, no license key, no validation backend: being installed from
// the Store *is* the license, detected via MSIX package identity. The
// portable GitHub build runs unpackaged and stays free. A self-built MSIX
// unlocks Pro too; the repo is open source, so this is a nudge, not
// protection.

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:win32/win32.dart';
import 'package:wsl2distromanager/components/helpers.dart';

enum LicensePlan { none, store }

/// GetCurrentPackageFullName's "this process has no package identity" code
/// (APPMODEL_ERROR_NO_PACKAGE) — not exported by package:win32.
const int _appModelErrorNoPackage = 15700;

class LicenseManager extends ChangeNotifier {
  static final LicenseManager _instance = LicenseManager._internal();
  factory LicenseManager() => _instance;
  LicenseManager._internal();

  bool _storeLicensed = false;

  /// Whether this process runs as a Store-installed (MSIX-packaged) app.
  bool get isStoreLicensed => _storeLicensed;

  /// Test seam — the real check asks about the test runner's process, which
  /// is never packaged. Reset to null in tearDown.
  @visibleForTesting
  static bool Function()? storeInstallCheckOverride;

  bool get isPro => _storeLicensed;

  LicensePlan get plan => _storeLicensed ? LicensePlan.store : LicensePlan.none;

  Future<void> init() async {
    _storeLicensed = _detectStoreInstall();

    // Cleanup of prefs from the retired subscription and legacy-claim
    // experiments.
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
      case LicensePlan.none:
        return 'plan-free';
    }
  }
}
