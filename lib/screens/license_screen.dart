import 'package:flutter/scheduler.dart';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:localization/localization.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wsl2distromanager/api/license_manager.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/components/constants.dart';
import 'package:wsl2distromanager/components/notify.dart';
import 'package:provider/provider.dart';

class LicenseScreen extends StatefulWidget {
  const LicenseScreen({Key? key}) : super(key: key);

  @override
  State<LicenseScreen> createState() => _LicenseScreenState();
}

class _LicenseScreenState extends State<LicenseScreen> {
  bool _isLoading = false;

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
    // No canLaunchUrl gate: on Windows it reports false for perfectly
    // launchable https URLs, which silently disabled the one thing this
    // screen asks the user to do (audit PS-07).
    try {
      await launchUrl(Uri.parse(windowsStoreUrl),
          mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    // .value(), not create(): Provider must not dispose() this app-wide
    // singleton when the screen unmounts.
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
                          _buildHeader(manager),
                          const SizedBox(height: 24),

                          if (manager.isPro) ...[
                            _buildStatusCard(manager),
                            const SizedBox(height: 20),
                            // The feature list used to live only in the
                            // non-Pro branch, so a paying user could never
                            // see what their plan includes (audit PS-04).
                            Card(
                              padding: const EdgeInsets.all(20),
                              borderRadius: BorderRadius.circular(10),
                              child: _buildComparisonTable(),
                            ),
                          ] else ...[
                            // Not Pro: lead with the pitch, status after.
                            _buildStoreSection(),
                            const SizedBox(height: 20),
                            _buildStatusCard(manager),
                            const SizedBox(height: 12),
                            _buildRestoreRow(),
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

  /// "Already bought Pro but the app shows Free?" — the entitlement probe is
  /// a single package-identity check with, before this, no way to re-run it
  /// visibly and no support path when it is wrong (audit PS-05).
  Widget _buildRestoreRow() {
    return Row(
      children: [
        Text('restore-hint-text'.i18n(),
            style: TextStyle(
                fontSize: 12, color: secondaryTextColor(context))),
        const SizedBox(width: 8),
        Button(
          key: const ValueKey('test-license-recheck'),
          onPressed: () async {
            await _loadStatus();
            if (!mounted) return;
            Notify.message(
                LicenseManager().isPro
                    ? 'restore-found-text'.i18n()
                    : 'restore-notfound-text'.i18n(),
                severity: LicenseManager().isPro
                    ? InfoBarSeverity.success
                    : InfoBarSeverity.warning);
          },
          child: Text('restore-check-text'.i18n()),
        ),
        const SizedBox(width: 8),
        HyperlinkButton(
          onPressed: () async {
            try {
              await launchUrl(Uri.parse(githubIssues),
                  mode: LaunchMode.externalApplication);
            } catch (_) {}
          },
          child: Text('restore-support-text'.i18n()),
        ),
      ],
    );
  }

  Widget _buildHeader(LicenseManager manager) {
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
            // The nav item and the page it opens now share a name — the nav
            // said "Upgrade to Pro" and the page said "License" (audit PS-06).
            Text(
              manager.isPro
                  ? 'license-text'.i18n()
                  : 'upgrade-pro-text'.i18n(),
              style: FluentTheme.of(context).typography.titleLarge,
            ),
            const SizedBox(height: 2),
            Text(
              'store-buy-info-text'.i18n(),
              style: FluentTheme.of(context).typography.bodyStrong?.copyWith(
                    color: secondaryTextColor(context),
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
    final color = isPro
        ? FluentTheme.of(context).accentColor
        : secondaryTextColor(context);
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
                  isPro
                      ? 'plan-store-detail'.i18n()
                      : 'plan-free-detail'.i18n(),
                  style: const TextStyle(fontSize: 14, height: 1.4),
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
            style: TextStyle(fontSize: 13, color: secondaryTextColor(context)),
          ),
          const SizedBox(height: 8),
          // The one question every buyer has first was the one thing the
          // screen never answered (audit PS-02). The number is the US Store
          // price; the button's Store page shows the buyer's own.
          Text(
            'store-price-text'.i18n(),
            key: const ValueKey('test-license-price'),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
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
      // "Smart Recommendations" and "Script Generation" are gone: the first
      // ships in the free tier and the second does not exist anywhere in the
      // app, so both rows were selling something other than what Pro is
      // (audit PS-01).
      ['error-diagnosis-feature', false, true],
      ['ai-workspace-feature', false, true],
    ];

    const columnWidth = 64.0;
    Widget cell(bool included) => SizedBox(
          width: columnWidth,
          child: Semantics(
            label: included
                ? 'included-text'.i18n()
                : 'notincluded-text'.i18n(),
            child: Icon(
              included ? FluentIcons.check_mark : FluentIcons.cancel,
              size: 14,
              color: included ? accent : secondaryTextColor(context),
            ),
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
            border: Border.all(color: surfaceBorderColor(context)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: subtleFillColor(context),
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(8)),
                ),
                child: Row(
                  children: [
                    const Expanded(child: SizedBox.shrink()),
                    SizedBox(
                      width: columnWidth,
                      child: Text('plan-free-short'.i18n(),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11,
                              color: secondaryTextColor(context))),
                    ),
                    SizedBox(
                      width: columnWidth,
                      child: Text('plan-pro-short'.i18n(),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('* ',
                style: TextStyle(
                    fontSize: 11, color: secondaryTextColor(context))),
            Expanded(
              child: Text(
                'byok-required-note'.i18n(),
                style: TextStyle(
                    fontSize: 11,
                    height: 1.4,
                    color: secondaryTextColor(context)),
              ),
            ),
          ],
        ),
      ],
    );
  }

}
