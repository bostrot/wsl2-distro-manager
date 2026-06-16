import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:wsl2distromanager/components/helpers.dart';

enum LicenseStatus { unknown, free, active, expired, suspended }

enum LicensePlan { none, monthly, yearly }

class LicenseInfo {
  final String key;
  final LicenseStatus status;
  final LicensePlan plan;
  final DateTime? expiresAt;
  final bool isTrial;
  final DateTime activatedAt;

  LicenseInfo({
    required this.key,
    required this.status,
    required this.plan,
    this.expiresAt,
    this.isTrial = false,
    required this.activatedAt,
  });

  factory LicenseInfo.fromJson(Map<String, dynamic> json) {
    return LicenseInfo(
      key: json['key'] as String? ?? '',
      status: LicenseStatus.values.firstWhere(
        (e) => e.toString() == 'LicenseStatus.${json['status']}',
        orElse: () => LicenseStatus.unknown,
      ),
      plan: LicensePlan.values.firstWhere(
        (e) => e.toString() == 'LicensePlan.${json['plan']}',
        orElse: () => LicensePlan.none,
      ),
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'] as String)
          : null,
      isTrial: json['is_trial'] as bool? ?? false,
      activatedAt: json['activated_at'] != null
          ? DateTime.parse(json['activated_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'status': status.toString().split('.').last,
      'plan': plan.toString().split('.').last,
      'expires_at': expiresAt?.toIso8601String(),
      'is_trial': isTrial,
      'activated_at': activatedAt.toIso8601String(),
    };
  }
}

class LicenseManager extends ChangeNotifier {
  static final LicenseManager _instance = LicenseManager._internal();
  factory LicenseManager() => _instance;
  LicenseManager._internal();

  final Dio _dio = Dio();

  // Backend URL for license validation (n8n endpoint)
  String get _backendUrl => 'https://n8n.aachen.dev/webhook/wsl-manager';

  LicenseStatus _status = LicenseStatus.unknown;
  LicensePlan _plan = LicensePlan.none;
  DateTime? _expiresAt;
  bool _isTrial = false;
  String _storedKey = '';
  // Grace period: if validation fails, trust cached status for this long
  static const Duration gracePeriod = Duration(days: 30);

  LicenseStatus get status => _status;
  LicensePlan get plan => _plan;
  DateTime? get expiresAt => _expiresAt;
  bool get isTrial => _isTrial;
  bool get isPro =>
      _status == LicenseStatus.active &&
      (_expiresAt == null || _expiresAt!.isAfter(DateTime.now()));
  bool get isExpired =>
      _status == LicenseStatus.expired ||
      (_expiresAt != null && _expiresAt!.isBefore(DateTime.now()));

  Future<void> init() async {
    _storedKey = prefs.getString('LicenseKey') ?? '';

    if (_storedKey.isEmpty) {
      _status = LicenseStatus.free;
      notifyListeners();
      return;
    }

    // Check cached status first for fast startup
    final cachedCheck =
        DateTime.tryParse(prefs.getString('LicenseLastCheck') ?? '');
    if (cachedCheck != null &&
        DateTime.now().difference(cachedCheck) < const Duration(hours: 1)) {
      _loadCachedStatus();
      notifyListeners();
    }

    // Validate in background (non-blocking)
    validateKey(_storedKey, silent: true).onError((_, __) {});
  }

  Future<void> activate(String key) async {
    final trimmed = key.trim().toUpperCase();

    if (trimmed.isEmpty) {
      throw Exception('Empty license key');
    }

    prefs.setString('LicenseKey', trimmed);
    _storedKey = trimmed;

    await validateKey(trimmed, silent: false);
  }

  Future<void> validateKey(String key, {bool silent = false}) async {
    try {
      final response = await _dio.get(
        '$_backendUrl/validate',
        queryParameters: {'license': key},
        options: Options(
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

      if (response.statusCode == 200) {
        final data = response.data;
        final valid = data['valid'];

        if (valid) {
          _status = LicenseStatus.active;
          _plan = LicensePlan.values.firstWhere(
            (e) => e.toString() == 'LicensePlan.${data['plan']}',
            orElse: () => LicensePlan.monthly,
          );
          _expiresAt = data['expires_at'] != null
              ? DateTime.parse(data['expires_at'] as String)
              : null;
          _isTrial = data['is_trial'] as bool? ?? false;

          // Cache status
          prefs.setString('LicenseLastCheck', DateTime.now().toIso8601String());
          prefs.setString('LicenseStatus', _status.toString().split('.').last);
          prefs.setString('LicensePlan', _plan.toString().split('.').last);
          if (_expiresAt != null) {
            prefs.setString('LicenseExpiresAt', _expiresAt!.toIso8601String());
          }
          prefs.setBool('LicenseIsTrial', _isTrial);
        } else {
          final reason = data['reason'] as String? ?? 'unknown';
          if (reason == 'expired') {
            _status = LicenseStatus.expired;
          } else if (reason == 'suspended') {
            _status = LicenseStatus.suspended;
          } else {
            _status = LicenseStatus.unknown;
          }
          // Clear invalid key
          prefs.remove('LicenseKey');
          _storedKey = '';
        }

        notifyListeners();
      }
    } catch (e) {
      if (!silent && kDebugMode) {
        debugPrint('License validation failed: $e');
      }

      // On error, use cached status with grace period
      final cachedCheck =
          DateTime.tryParse(prefs.getString('LicenseLastCheck') ?? '');
      if (cachedCheck != null &&
          DateTime.now().difference(cachedCheck) < gracePeriod) {
        _loadCachedStatus();
      } else if (_storedKey.isNotEmpty) {
        // Never validated successfully, treat as invalid
        _status = LicenseStatus.unknown;
      }
      notifyListeners();
    }
  }

  void _loadCachedStatus() {
    final statusStr = prefs.getString('LicenseStatus');
    if (statusStr != null) {
      _status = LicenseStatus.values.firstWhere(
        (e) => e.toString().split('.').last == statusStr,
        orElse: () => LicenseStatus.unknown,
      );
    }

    final planStr = prefs.getString('LicensePlan');
    if (planStr != null) {
      _plan = LicensePlan.values.firstWhere(
        (e) => e.toString().split('.').last == planStr,
        orElse: () => LicensePlan.none,
      );
    }

    final expiresStr = prefs.getString('LicenseExpiresAt');
    if (expiresStr != null) {
      _expiresAt = DateTime.tryParse(expiresStr);
    }

    _isTrial = prefs.getBool('LicenseIsTrial') ?? false;
  }

  Future<void> deactivate() async {
    prefs.remove('LicenseKey');
    prefs.remove('LicenseLastCheck');
    prefs.remove('LicenseStatus');
    prefs.remove('LicensePlan');
    prefs.remove('LicenseExpiresAt');
    prefs.remove('LicenseIsTrial');

    _status = LicenseStatus.free;
    _plan = LicensePlan.none;
    _expiresAt = null;
    _isTrial = false;
    _storedKey = '';

    notifyListeners();
  }

  String getStatusText() {
    switch (_status) {
      case LicenseStatus.active:
        if (_isTrial) return 'trial-active';
        if (_expiresAt != null && _expiresAt!.isBefore(DateTime.now())) {
          return 'license-expired';
        }
        return 'license-active';
      case LicenseStatus.expired:
        return 'license-expired';
      case LicenseStatus.suspended:
        return 'license-suspended';
      case LicenseStatus.free:
        return 'license-free';
      case LicenseStatus.unknown:
        return 'license-unknown';
    }
  }

  String getPlanText() {
    switch (_plan) {
      case LicensePlan.monthly:
        return 'plan-monthly';
      case LicensePlan.yearly:
        return 'plan-yearly';
      default:
        return 'plan-free';
    }
  }
}
