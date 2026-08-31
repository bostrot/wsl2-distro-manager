import 'package:fluent_ui/fluent_ui.dart';
import 'package:localization/localization.dart';

/// Amber "BETA" pill marking features that ship before they are fully
/// polished. Amber rather than the accent color so it does not read as
/// [ProBadge]. The label stays untranslated.
class BetaBadge extends StatelessWidget {
  const BetaBadge({super.key});

  /// The badge's wash and border colour.
  static const Color color = Color(0xFFFFBF00);

  /// The text colour, per brightness. Raw amber on its own wash measured
  /// **1.40:1** over a light background and 5.89:1 over a dark one — the one
  /// defect in the theme pass that dark mode passed and light mode failed
  /// (audit TL-05, PS-09). The darkened amber clears AA on the light wash.
  static Color foregroundFor(Brightness brightness) =>
      brightness == Brightness.dark ? color : const Color(0xFF7A5C00);

  @override
  Widget build(BuildContext context) {
    final foreground = foregroundFor(FluentTheme.of(context).brightness);
    return Semantics(
      label: 'beta-badge-label-text'.i18n(),
      excludeSemantics: true,
      child: Tooltip(
        message: 'beta-info-text'.i18n(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(3),
            border:
                Border.all(color: color.withValues(alpha: 0.5), width: 0.5),
          ),
          child: Text(
            'BETA',
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.bold,
              color: foreground,
              letterSpacing: 0.5,
            ),
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
