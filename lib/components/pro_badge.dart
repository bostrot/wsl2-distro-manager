import 'package:fluent_ui/fluent_ui.dart';
import 'package:localization/localization.dart';
import 'package:wsl2distromanager/api/license_manager.dart';
import 'package:wsl2distromanager/nav/router.dart';

class ProBadge extends StatelessWidget {
  const ProBadge({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final accent = FluentTheme.of(context).accentColor;
    return Tooltip(
      message: 'pro-feature-text'.i18n(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              accent.withValues(alpha: 0.3),
              accent.withValues(alpha: 0.1),
            ],
          ),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: accent.withValues(alpha: 0.5),
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(FluentIcons.crown, size: 10, color: accent),
            const SizedBox(width: 3),
            Text(
              'Pro',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ProFeatureWrapper extends StatelessWidget {
  final Widget child;
  final String featureKey;

  const ProFeatureWrapper({
    Key? key,
    required this.child,
    required this.featureKey,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.topRight,
      children: [
        child,
        Positioned(
          right: 8,
          top: 8,
          child: _buildProOverlay(context),
        ),
      ],
    );
  }

  Widget _buildProOverlay(BuildContext context) {
    final isPro = LicenseManager().isPro;

    if (isPro) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: FluentTheme.of(context).brightness.isDark
            ? Colors.black.withValues(alpha: 0.7)
            : Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(FluentIcons.crown,
              size: 12, color: FluentTheme.of(context).accentColor),
          const SizedBox(width: 4),
          Text(
            'Pro',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: FluentTheme.of(context).accentColor,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              router.pushNamed('license');
            },
            child: Text(
              'upgrade-text'.i18n(),
              style: TextStyle(
                fontSize: 10,
                color: FluentTheme.of(context).accentColor,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class UpgradePrompt extends StatelessWidget {
  final String messageKey;
  final VoidCallback? onUpgrade;

  const UpgradePrompt({
    Key? key,
    required this.messageKey,
    this.onUpgrade,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (LicenseManager().isPro) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluentTheme.of(context).accentColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: FluentTheme.of(context).accentColor.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(
            FluentIcons.crown,
            size: 16,
            color: FluentTheme.of(context).accentColor,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              messageKey.i18n(),
              style: const TextStyle(fontSize: 12),
            ),
          ),
          Button(
            onPressed: onUpgrade ?? () => router.pushNamed('license'),
            child: Text('upgrade-text'.i18n()),
          ),
        ],
      ),
    );
  }
}
