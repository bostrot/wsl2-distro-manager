import 'package:fluent_ui/fluent_ui.dart';
import 'package:localization/localization.dart';

/// Amber "BETA" pill for features that ship before they're fully polished —
/// so users know which parts to expect rough edges in (and where feedback
/// is most useful) without holding the whole release back for them.
///
/// Same visual language as [ProBadge] (compact pill, tiny bold label,
/// tooltip on hover), deliberately in a warm amber rather than the accent
/// color so the two read as different things at a glance. The label itself
/// is intentionally not translated — "BETA" is universally understood, and
/// keeping it fixed means tests can find it without a localization delegate.
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

/// Screen-level beta notice, for pages that are beta in their entirety
/// (e.g. AI Workspace) rather than a single control.
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
