import 'package:flutter/scheduler.dart';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:localization/localization.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wsl2distromanager/api/license_manager.dart';
import 'package:wsl2distromanager/components/constants.dart';
import 'package:wsl2distromanager/components/notify.dart';
import 'package:provider/provider.dart';

class LicenseScreen extends StatefulWidget {
  const LicenseScreen({Key? key}) : super(key: key);

  @override
  State<LicenseScreen> createState() => _LicenseScreenState();
}

class _LicenseScreenState extends State<LicenseScreen> {
  final TextEditingController _legacyEmailController = TextEditingController();
  bool _isLoading = false;
  bool _isClaimingLegacy = false;
  String _legacyClaimError = '';

  @override
  void initState() {
    super.initState();
    // Defer init to avoid setState during build (LicenseManager ChangeNotifier
    // triggers Provider rebuilds that cascade into this widget's build phase)
    SchedulerBinding.instance.addPostFrameCallback((_) => _loadStatus());
  }

  Future<void> _loadStatus() async {
    setState(() {
      _isLoading = true;
    });
    await LicenseManager().init();
    if (!mounted) return;
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _openStorePage() async {
    final uri = Uri.parse(windowsStoreUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _claimLegacyPro() {
    final email = _legacyEmailController.text.trim();
    setState(() => _isClaimingLegacy = true);

    final granted = LicenseManager().claimLegacyPro(email);

    if (!mounted) return;
    setState(() {
      _isClaimingLegacy = false;
      _legacyClaimError = granted ? '' : 'thank-you-invalid-email'.i18n();
    });

    if (granted) {
      _legacyEmailController.clear();
      Notify.message('thank-you-claim-success'.i18n());
    }
  }

  @override
  Widget build(BuildContext context) {
    // LicenseManager is an app-wide singleton (see LicenseManager._internal).
    // Use .value(), not create(), so Provider doesn't dispose() the shared
    // instance when this screen unmounts — that would permanently break
    // Pro-gating (AI chat, AI Workspace, etc.) for the rest of the app.
    return ChangeNotifierProvider.value(
      value: LicenseManager(),
      child: Consumer<LicenseManager>(
        builder: (context, manager, _) {
          if (_isLoading) {
            return const Center(child: ProgressRing());
          }

          return Column(
            mainAxisSize: MainAxisSize.max,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHeader(),
                          const SizedBox(height: 24),

                          // Thank-you note for early purchasers using the
                          // GitHub build (only relevant while the claim
                          // window is open, or if already claimed, as a
                          // standing thank-you).
                          if (manager.hasLegacyPro ||
                              (!manager.isPro &&
                                  manager.isLegacyClaimWindowOpen)) ...[
                            _buildThankYouCard(manager),
                            const SizedBox(height: 20),
                          ],

                          if (manager.isPro) ...[
                            _buildStatusCard(manager),
                          ] else ...[
                            // Not Pro: this is the GitHub build. The pitch
                            // is the headline — one-time Store purchase.
                            _buildStoreSection(),
                            const SizedBox(height: 20),
                            _buildStatusCard(manager),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildThankYouCard(LicenseManager manager) {
    final accent = FluentTheme.of(context).accentColor;

    if (manager.hasLegacyPro) {
      return Card(
        padding: const EdgeInsets.all(20),
        borderRadius: BorderRadius.circular(10),
        backgroundColor: accent.withValues(alpha: 0.06),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(FluentIcons.heart, size: 20, color: accent),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'thank-you-already-claimed-title'.i18n(),
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'thank-you-already-claimed-text'.i18n(),
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      padding: const EdgeInsets.all(20),
      borderRadius: BorderRadius.circular(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(FluentIcons.heart, size: 18, color: accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'thank-you-title-text'.i18n(),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'thank-you-body-text'.i18n(),
            style: const TextStyle(fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 8),
          Text(
            'thank-you-offer-text'.i18n(),
            style: const TextStyle(fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 8),
          Text(
            'thank-you-oss-text'.i18n(),
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              fontStyle: FontStyle.italic,
              color: accent,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextBox(
                  key: const ValueKey('test-legacy-email-input'),
                  controller: _legacyEmailController,
                  placeholder: 'thank-you-email-placeholder'.i18n(),
                  onChanged: (_) => setState(() => _legacyClaimError = ''),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const ValueKey('test-legacy-claim-button'),
                onPressed: _isClaimingLegacy ? null : _claimLegacyPro,
                child: _isClaimingLegacy
                    ? const SizedBox(
                        width: 16, height: 16, child: ProgressRing())
                    : Text('thank-you-claim-btn'.i18n()),
              ),
            ],
          ),
          if (_legacyClaimError.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _legacyClaimError,
              style: TextStyle(fontSize: 12, color: Colors.red),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final accent = FluentTheme.of(context).accentColor;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                accent.withValues(alpha: 0.25),
                accent.withValues(alpha: 0.08),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(FluentIcons.crown, size: 22, color: accent),
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'license-text'.i18n(),
              style: FluentTheme.of(context).typography.titleLarge,
            ),
            const SizedBox(height: 2),
            Text(
              'store-buy-info-text'.i18n(),
              style: FluentTheme.of(context).typography.bodyStrong?.copyWith(
                    color: Colors.grey,
                    fontWeight: FontWeight.normal,
                  ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatusCard(LicenseManager manager) {
    final isPro = manager.isPro;
    final color = isPro ? FluentTheme.of(context).accentColor : Colors.grey;
    final isDark = FluentTheme.of(context).brightness.isDark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: isDark ? 0.16 : 0.12),
            color.withValues(alpha: isDark ? 0.04 : 0.03),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isPro ? FluentIcons.crown : FluentIcons.info,
              color: color,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isPro ? 'plan-pro'.i18n() : 'plan-free'.i18n(),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  manager.getPlanText().i18n(),
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStoreSection() {
    return Card(
      padding: const EdgeInsets.all(20),
      borderRadius: BorderRadius.circular(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'store-buy-title'.i18n(),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'store-buy-detail-text'.i18n(),
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const ValueKey('test-license-store-button'),
              onPressed: _openStorePage,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(FluentIcons.shop, size: 16),
                    const SizedBox(width: 8),
                    Text('store-buy-btn'.i18n()),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          _buildComparisonTable(),
        ],
      ),
    );
  }

  Widget _buildComparisonTable() {
    final accent = FluentTheme.of(context).accentColor;
    // Each row: [i18n key, included in Free, included in Pro].
    final rows = <List<Object>>[
      ['core-wsl-management-feature', true, true],
      ['ai-config-assistant-feature', false, true],
      ['smart-recommendations-feature', false, true],
      ['script-generation-feature', false, true],
      ['error-diagnosis-feature', false, true],
      ['ai-workspace-feature', false, true],
    ];

    Widget cell(bool included) => SizedBox(
          width: 44,
          child: Icon(
            included ? FluentIcons.check_mark : FluentIcons.cancel,
            size: 14,
            color: included ? accent : Colors.grey.withValues(alpha: 0.4),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'compare-plans-text'.i18n(),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.06),
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(8)),
                ),
                child: Row(
                  children: [
                    const Expanded(child: SizedBox.shrink()),
                    SizedBox(
                      width: 44,
                      child: Text('plan-free'.i18n(),
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey)),
                    ),
                    SizedBox(
                      width: 44,
                      child: Text('plan-pro'.i18n(),
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: accent)),
                    ),
                  ],
                ),
              ),
              for (final row in rows)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text((row[0] as String).i18n(),
                            style: const TextStyle(fontSize: 12)),
                      ),
                      cell(row[1] as bool),
                      cell(row[2] as bool),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _legacyEmailController.dispose();
    super.dispose();
  }
}
