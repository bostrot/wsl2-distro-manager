import 'package:fluent_ui/fluent_ui.dart';
import 'package:localization/localization.dart';

/// Amber "BETA" pill marking features that ship before they are fully
/// polished. Amber rather than the accent color so it does not read as
/// [ProBadge]. The label stays untranslated.
class BetaBadge extends StatelessWidget {
  const BetaBadge({super.key});

  static const Color color = Color(0xFFFFBF00);

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'beta-info-text'.i18n(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: color.withValues(alpha: 0.5), width: 0.5),
        ),
        child: const Text(
          'BETA',
          style: TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.bold,
            color: color,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

/// Screen-level notice for pages that are beta in their entirety.
class BetaBanner extends StatelessWidget {
  const BetaBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return InfoBar(
      title: Text('beta-banner-title'.i18n()),
      content: Text('beta-info-text'.i18n()),
      severity: InfoBarSeverity.warning,
    );
  }
}
