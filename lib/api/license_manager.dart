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

/// How the current Pro entitlement (if any) was obtained.
enum LicensePlan { none, store, legacy }

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

  bool get isPro => hasLegacyPro || _storeLicensed;

  LicensePlan get plan {
    if (hasLegacyPro) return LicensePlan.legacy;
    if (_storeLicensed) return LicensePlan.store;
    return LicensePlan.none;
  }

  Future<void> init() async {
    _storeLicensed = _detectStoreInstall();

    // Cleanup of prefs from the retired subscription experiment.
    for (final key in [
      'LicenseKey',
      'LicenseLastCheck',
      'LicenseStatus',
      'LicensePlan',
      'LicenseExpiresAt',
      'LicenseIsTrial',
    ]) {
      prefs.remove(key);
    }

    notifyListeners();
  }

  bool _detectStoreInstall() {
    final override = storeInstallCheckOverride;
    if (override != null) return override();
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

  // Legacy grant for people who bought before the current pricing existed.
  // Honor-system: Store purchase records cannot be checked from here, so
  // exposure is bounded by [legacyClaimWindowCloses].

  /// Claims made after this date are no longer accepted.
  static final DateTime legacyClaimWindowCloses = DateTime(2026, 11, 2);

  bool get isLegacyClaimWindowOpen =>
      DateTime.now().isBefore(legacyClaimWindowCloses);

  bool get hasLegacyPro => prefs.getBool('LegacyProGranted') ?? false;

  String? get legacyProEmail => prefs.getString('LegacyProEmail');

  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  /// Grants permanent local Pro. False if [email] is malformed or the claim
  /// window has closed.
  bool claimLegacyPro(String email) {
    final trimmed = email.trim();
    if (!_emailPattern.hasMatch(trimmed) || !isLegacyClaimWindowOpen) {
      return false;
    }

    prefs.setBool('LegacyProGranted', true);
    prefs.setString('LegacyProEmail', trimmed);
    prefs.setString('LegacyProClaimedAt', DateTime.now().toIso8601String());
    notifyListeners();
    return true;
  }

  String getPlanText() {
    switch (plan) {
      case LicensePlan.legacy:
        return 'plan-legacy';
      case LicensePlan.store:
        return 'plan-store';
      case LicensePlan.none:
        return 'plan-free';
    }
  }
}
