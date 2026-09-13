import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plausible_analytics/plausible_analytics.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wsl2distromanager/api/license_manager.dart';
import 'package:wsl2distromanager/api/purchase_routes.dart';
import 'package:wsl2distromanager/api/vm/vm_platform.dart';
import 'package:wsl2distromanager/components/analytics.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/screens/license_screen.dart';

/// The License page renders one card per purchase route this host offers, and
/// — since Windows now also sells a key on the website — the key-entry box on
/// every host, not just the Mac.
///
/// Without a localization delegate every label renders as its raw i18n key,
/// which is what the copy assertions below look for.
const Size _kSurface = Size(1200, 2400);

/// One reported event, kept rather than posted.
class _Reported {
  const _Reported(this.name, this.page, this.props);

  final String name;
  final String page;
  final Map<String, String> props;
}

/// Records what the screen reports instead of posting it, so the paywall's
/// own numbers can be asserted rather than taken on trust.
class _RecordingPlausible implements Plausible {
  final List<_Reported> events = [];

  @override
  Future<int> event({
    String name = 'pageview',
    String referrer = '',
    String page = '',
    Map<String, String> props = const {},
  }) async {
    events.add(_Reported(name, page, props));
    return 200;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _page({bool? appleHost}) => FluentApp(
    home: ScaffoldPage(content: LicenseScreen(appleHost: appleHost)));

void main() {
  late _RecordingPlausible analytics;
  late Plausible realPlausible;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    LicenseManager.storeInstallCheckOverride = () => false;
    LicenseManager.httpOverride = null;
    await LicenseManager().init();
    realPlausible = plausible;
    analytics = _RecordingPlausible();
    plausible = analytics;
  });

  tearDown(() async {
    plausible = realPlausible;
    LicenseManager.storeInstallCheckOverride = null;
    LicenseManager.httpOverride = null;
    await LicenseManager().clearLicense();
  });

  testWidgets('a free install is offered every route this host sells',
      (tester) async {
    await tester.binding.setSurfaceSize(_kSurface);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_page());
    await tester.pumpAndSettle();

    final routes = purchaseRoutesFor(apple: isAppleHost);
    for (final route in routes) {
      expect(find.text(route.buttonKey), findsOneWidget,
          reason: 'no CTA for ${route.id}');
      expect(find.text(route.priceKey), findsOneWidget,
          reason: 'no price for ${route.id}');
    }
    // The lead CTA keeps the key the rest of the suite already looks for.
    expect(find.byKey(const ValueKey('test-license-store-button')),
        findsOneWidget);
  });

  testWidgets('the key box is offered on every host, not only the Mac',
      (tester) async {
    await tester.binding.setSurfaceSize(_kSurface);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_page());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('test-license-key-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('test-license-activate')), findsOneWidget);
    expect(find.text(activateDetailKeyFor(apple: isAppleHost)), findsOneWidget);
  });

  testWidgets('the plan comparison is shown once, not once per buy card',
      (tester) async {
    // It used to live inside the single buy card; with two cards on Windows
    // that would print the whole table twice.
    await tester.binding.setSurfaceSize(_kSurface);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_page());
    await tester.pumpAndSettle();

    expect(find.text('compare-plans-text'), findsOneWidget);
  });

  testWidgets('Windows is offered the Store and the website, in that order',
      (tester) async {
    // The point of the change, and unreachable from a Mac dev host without
    // the screen's host seam.
    await tester.binding.setSurfaceSize(_kSurface);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_page(appleHost: false));
    await tester.pumpAndSettle();

    final routes = purchaseRoutesFor(apple: false);
    expect(routes.length, 2);
    for (final route in routes) {
      expect(find.text(route.buttonKey), findsOneWidget);
      expect(find.text(route.priceKey), findsOneWidget);
    }
    // Both CTAs are present and separately addressable.
    expect(find.byKey(const ValueKey('test-license-store-button')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('test-license-web-buy-button')),
        findsOneWidget);
    // One table under both cards, and the key box a Store-only Windows build
    // never used to show.
    expect(find.text('compare-plans-text'), findsOneWidget);
    expect(find.byKey(const ValueKey('test-license-key-field')), findsOneWidget);
    expect(find.text(activateDetailKeyFor(apple: false)), findsOneWidget);
  });

  testWidgets('the Store CTA sits above the website one on Windows',
      (tester) async {
    await tester.binding.setSurfaceSize(_kSurface);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_page(appleHost: false));
    await tester.pumpAndSettle();

    final store = tester.getTopLeft(
        find.byKey(const ValueKey('test-license-store-button')));
    final web = tester.getTopLeft(
        find.byKey(const ValueKey('test-license-web-buy-button')));

    // The Store stays the primary, cheaper route; the website is the way out
    // of it, not the headline.
    expect(store.dy, lessThan(web.dy));
  });

  testWidgets('opening the paywall is reported, like every other screen',
      (tester) async {
    // Without it there is no denominator: the share of people who reach the
    // paywall and never buy cannot be told from the share who never got here.
    await tester.binding.setSurfaceSize(_kSurface);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_page());
    await tester.pumpAndSettle();

    expect(analytics.events.where((e) => e.page == 'license').length, 1);
  });

  testWidgets('each buy CTA reports which route was taken', (tester) async {
    // The Store and the website are counted apart deliberately: the Store is
    // the cheaper Windows route and its sales never touch the website, so a
    // single "clicked buy" total cannot be compared with anything.
    await tester.binding.setSurfaceSize(_kSurface);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_page(appleHost: false));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('test-license-store-button')));
    // Settled, not pumped: the CTA leaves a short press-feedback timer behind
    // and an unfinished one fails the test on its own.
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('test-license-web-buy-button')));
    await tester.pumpAndSettle();

    final clicks =
        analytics.events.where((e) => e.name == 'license_buy_clicked').toList();
    expect(clicks.map((e) => e.props['route']).toList(), ['store', 'direct']);
    for (final click in clicks) {
      expect(click.props['host'], 'windows');
    }
  });

  testWidgets('a licensed install is sold nothing and asked for no key',
      (tester) async {
    LicenseManager.storeInstallCheckOverride = () => true;
    await LicenseManager().init();

    await tester.binding.setSurfaceSize(_kSurface);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_page());
    await tester.pumpAndSettle();

    expect(LicenseManager().isPro, true);
    for (final route in purchaseRoutesFor(apple: isAppleHost)) {
      expect(find.text(route.buttonKey), findsNothing);
    }
    expect(find.byKey(const ValueKey('test-license-key-field')), findsNothing);
    // The feature list stays, so a paying user can still see what they have.
    expect(find.text('compare-plans-text'), findsOneWidget);
  });
}
