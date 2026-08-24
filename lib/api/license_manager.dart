// Pro entitlement for the one-time-purchase model.
//
// The app is sold as a one-time purchase on the Microsoft Store; the GitHub
// release is the same code, free, with Pro features behind this gate. There
// is no subscription, no license key, and no validation backend: being
// installed from the Store *is* the license. Detection works via MSIX
// package identity — a Store install always runs with package identity,
// while the portable GitHub build does not. (Someone side-loading a
// self-built MSIX gets Pro too; the codebase is open source, so any gate
// here is an honor-system nudge, not protection — same reasoning as the
// legacy grant below.)

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

  // -----------------------------------------------------------------------
  // Store entitlement
  // -----------------------------------------------------------------------

  bool _storeLicensed = false;

  /// Whether this process runs as a Store-installed (MSIX-packaged) app.
  bool get isStoreLicensed => _storeLicensed;

  /// Test seam for the package-identity check — the real check asks the OS
  /// about the *test runner's* process, which is never packaged. Reset to
  /// null in tearDown; the singleton outlives individual tests.
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

    // One-time cleanup of prefs left over from the retired Stripe
    // subscription experiment (never shipped beyond test mode).
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
        // With no package identity this returns APPMODEL_ERROR_NO_PACKAGE;
        // with identity it returns ERROR_INSUFFICIENT_BUFFER (buffer too
        // small for the name we don't actually need).
        final result = GetCurrentPackageFullName(length, nullptr);
        return result != _appModelErrorNoPackage;
      });
    } catch (_) {
      // FFI failure — assume unpackaged rather than crashing the gate.
      return false;
    }
  }

  // -----------------------------------------------------------------------
  // Legacy "thank you" grant.
  //
  // A goodwill gesture for people who bought the app before the current
  // pricing existed: a permanent, free Pro grant claimed by entering the
  // purchase email on the License screen. This is intentionally
  // client-side only and NOT backend-verified — there's no way to
  // cross-check Microsoft Store purchase records here — so it's an
  // honor-system claim. Exposure is bounded by [legacyClaimWindowCloses]:
  // once that date passes, the claim UI disappears entirely (grants made
  // before then remain permanent).
  // -----------------------------------------------------------------------

  /// Claims made after this date are no longer accepted.
  static final DateTime legacyClaimWindowCloses = DateTime(2026, 11, 2);

  bool get isLegacyClaimWindowOpen =>
      DateTime.now().isBefore(legacyClaimWindowCloses);

  bool get hasLegacyPro => prefs.getBool('LegacyProGranted') ?? false;

  String? get legacyProEmail => prefs.getString('LegacyProEmail');

  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  /// Grant a permanent local "legacy Pro" status. Returns false (granting
  /// nothing) if [email] doesn't look like an email or the claim window has
  /// already closed.
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
