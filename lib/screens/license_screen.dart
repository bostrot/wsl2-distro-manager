import 'package:flutter/scheduler.dart';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:localization/localization.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wsl2distromanager/api/license_manager.dart';
import 'package:wsl2distromanager/components/notify.dart';
import 'package:provider/provider.dart';

class LicenseScreen extends StatefulWidget {
  const LicenseScreen({Key? key}) : super(key: key);

  @override
  State<LicenseScreen> createState() => _LicenseScreenState();
}

class _LicenseScreenState extends State<LicenseScreen> {
  final TextEditingController _keyController = TextEditingController();
  bool _isLoading = false;
  bool _isActivating = false;
  String _errorMessage = '';

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

  Future<void> _activateKey() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      setState(() {
        _errorMessage = 'license-key-empty'.i18n();
      });
      return;
    }

    setState(() {
      _isActivating = true;
      _errorMessage = '';
    });

    try {
      await LicenseManager().activate(key);
      
      if (!mounted) return;
      
      final manager = LicenseManager();
      if (manager.isPro) {
        Notify.message('license-activated'.i18n());
        _keyController.clear();
      } else {
        setState(() {
          _errorMessage = 'license-invalid'.i18n();
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'license-error-activate'.i18n();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isActivating = false;
        });
      }
    }
  }

  Future<void> _openSubscriptionPage(String plan) async {
    final url = plan == 'monthly' 
        ? 'https://buy.stripe.com/test_6oU7sLd305PN2sFbqk1Fe00' 
        : 'https://buy.stripe.com/test_aFaeVdd30ba72sFdys1Fe01';
    
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _deactivate() async {
    await LicenseManager().deactivate();
    if (!mounted) return;
    Notify.message('license-deactivated'.i18n());
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => LicenseManager(),
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
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Status card
                      _buildStatusCard(manager),
                      const SizedBox(height: 20),
                      
                      // Activation section
                      _buildActivationSection(),
                      const SizedBox(height: 20),
                      
                      // Subscribe section (only show if not Pro)
                      if (!manager.isPro) ...[
                        _buildSubscribeSection(),
                      ],
                      
                      // Manage subscription (only for active Pro users)
                      if (manager.isPro && !manager.isTrial) ...[
                        const SizedBox(height: 20),
                        _buildManageSubscription(manager),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatusCard(LicenseManager manager) {
    final isPro = manager.isPro;
    final color = isPro 
        ? FluentTheme.of(context).accentColor 
        : Colors.grey;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isPro ? FluentIcons.check_mark : FluentIcons.info,
                color: color,
                size: 24,
              ),
              const SizedBox(width: 10),
              Text(
                isPro ? 'plan-pro'.i18n() : 'plan-free'.i18n(),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              if (manager.isTrial) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'trial-badge'.i18n(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.orange,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          
          // Plan details
          Text(
            'plan-${manager.plan.toString().split('.').last}'.i18n(),
            style: const TextStyle(fontSize: 14),
          ),
          
          if (manager.expiresAt != null) ...[
            const SizedBox(height: 4),
            Text(
              '${'expires-text'.i18n()}: ${_formatDate(manager.expiresAt!)}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
          
          if (!isPro && manager.status == LicenseStatus.expired) ...[
            const SizedBox(height: 8),
            Text(
              'license-expired-info'.i18n(),
              style: TextStyle(fontSize: 12, color: Colors.red),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActivationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'activate-license-text'.i18n(),
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextBox(
                key: const ValueKey('test-license-key-input'),
                controller: _keyController,
                placeholder: 'license-key-placeholder'.i18n(),
                onChanged: (_) => setState(() => _errorMessage = ''),
              ),
            ),
            const SizedBox(width: 8),
            Button(
              key: const ValueKey('test-license-activate-button'),
              onPressed: _isActivating ? null : _activateKey,
              child: _isActivating 
                  ? SizedBox(width: 16, height: 16, child: const ProgressRing())
                  : Text('activate-text'.i18n()),
            ),
          ],
        ),
        if (_errorMessage.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            _errorMessage,
            style: TextStyle(fontSize: 12, color: Colors.red),
          ),
        ],
        
        // Deactivate button for active users
        if (LicenseManager().isPro) ...[
          const SizedBox(height: 12),
          Button(
            onPressed: _deactivate,
            child: Text(
              'deactivate-license-text'.i18n(),
              style: const TextStyle(color: Colors.grey),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSubscribeSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: FluentTheme.of(context).brightness.isDark 
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'subscribe-text'.i18n(),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'subscribe-info-text'.i18n(),
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          
          // Pricing cards
          Row(
            children: [
              Expanded(
                child: _buildPricingCard(
                  title: 'plan-monthly'.i18n(),
                  price: '\$4.99',
                  period: '/${'month-text'.i18n()}',
                  description: 'monthly-info-text'.i18n(),
                  accent: false,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildPricingCard(
                  title: 'plan-yearly'.i18n(),
                  price: '\$39.99',
                  period: '/${'year-text'.i18n()}',
                  description: 'yearly-info-text'.i18n(),
                  accent: true,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Feature list
          Text(
            'pro-features-text'.i18n(),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          _buildFeatureItem('ai-config-assistant-feature'.i18n()),
          _buildFeatureItem('smart-recommendations-feature'.i18n()),
          _buildFeatureItem('script-generation-feature'.i18n()),
          _buildFeatureItem('error-diagnosis-feature'.i18n()),
        ],
      ),
    );
  }

  Widget _buildPricingCard({
    required String title,
    required String price,
    required String period,
    required String description,
    required bool accent,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accent 
            ? FluentTheme.of(context).accentColor.withValues(alpha: 0.1)
            : null,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: accent 
              ? FluentTheme.of(context).accentColor
              : Colors.grey.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: accent ? FluentTheme.of(context).accentColor : null,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                price,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  period,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: ValueKey(
              title.contains('monthly') || title.contains('Monatlich') 
                  ? 'test-license-monthly-link' 
                  : 'test-license-yearly-link',
            ),
            onPressed: () => _openSubscriptionPage(
              title.contains('monthly') || title.contains('Monatlich') 
                  ? 'monthly' 
                  : 'yearly',
            ),
            child: Text('subscribe-text'.i18n()),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(FluentIcons.check_mark, size: 14),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildManageSubscription(LicenseManager manager) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FluentTheme.of(context).brightness.isDark 
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'manage-subscription-text'.i18n(),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Button(
            onPressed: () async {
              final uri = Uri.parse('https://billing.stripe.com/p/login/test_6oU7sLd305PN2sFbqk1Fe00');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            child: Text('open-billing-portal-text'.i18n()),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }
}
