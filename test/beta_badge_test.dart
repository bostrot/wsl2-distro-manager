import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wsl2distromanager/components/beta_badge.dart';

void main() {
  testWidgets('BetaBadge renders a fixed, untranslated BETA label',
      (tester) async {
    await tester.pumpWidget(const FluentApp(home: BetaBadge()));

    // The label is deliberately hardcoded (like ProBadge's "Pro") so it
    // reads the same in every locale and is findable without a
    // localization delegate.
    expect(find.text('BETA'), findsOneWidget);
    expect(find.byType(Tooltip), findsOneWidget);
  });

  testWidgets('BetaBanner renders as a warning InfoBar', (tester) async {
    await tester.pumpWidget(const FluentApp(home: BetaBanner()));

    final infoBar = tester.widget<InfoBar>(find.byType(InfoBar));
    expect(infoBar.severity, InfoBarSeverity.warning);
  });
}
