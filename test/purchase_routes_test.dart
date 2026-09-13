import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wsl2distromanager/api/purchase_routes.dart';
import 'package:wsl2distromanager/components/constants.dart';

/// Which ways to buy Pro each host offers.
///
/// Windows used to have exactly one — the Microsoft Store — and the key-entry
/// box was hidden there, so a licence bought on the website could not be
/// redeemed on the machine it was bought for. Both routes are now offered,
/// and this pins the set rather than the screen, which cannot be pumped for
/// the other host from either dev machine.
void main() {
  Map<String, dynamic> englishStrings() =>
      json.decode(File('lib/i18n/en.json').readAsStringSync())
          as Map<String, dynamic>;

  group('purchaseRoutesFor', () {
    test('macOS sells only through the website', () {
      final routes = purchaseRoutesFor(apple: true);

      expect(routes.map((r) => r.id), [PurchaseRouteId.direct]);
      expect(routes.single.url, macBuyUrl);
    });

    test('Windows keeps the Store first and adds the website after it', () {
      final routes = purchaseRoutesFor(apple: false);

      expect(routes.map((r) => r.id).toList(),
          [PurchaseRouteId.store, PurchaseRouteId.direct]);
      expect(routes.first.url, windowsStoreUrl);
      expect(routes.last.url, windowsBuyUrl);
    });

    test('the Windows website route does not reuse the Mac price', () {
      // The two are deliberately different amounts; sharing the key would
      // quietly print the Mac price on the Windows card.
      final mac = purchaseRoutesFor(apple: true).single;
      final windows = purchaseRoutesFor(apple: false).last;

      expect(windows.priceKey, isNot(mac.priceKey));
      expect(windows.detailKey, isNot(mac.detailKey));
    });

    test('the two Windows cards never share their copy', () {
      final routes = purchaseRoutesFor(apple: false);
      final store = routes.first;
      final direct = routes.last;

      expect(direct.titleKey, isNot(store.titleKey));
      expect(direct.detailKey, isNot(store.detailKey));
      expect(direct.priceKey, isNot(store.priceKey));
      expect(direct.buttonKey, isNot(store.buttonKey));
      expect(direct.url, isNot(store.url));
    });

    test('the Windows price is stated, since a website sale shows no Store '
        'page to read it off', () {
      final en = englishStrings();
      final windows = purchaseRoutesFor(apple: false).last;

      expect(en[windows.priceKey], contains('14.99'));
    });
  });

  group('where the website route points', () {
    Uri directUrlFor({required bool apple}) => Uri.parse(
        purchaseRoutesFor(apple: apple)
            .firstWhere((r) => r.id == PurchaseRouteId.direct)
            .url);

    test('both quote the price for the host they were opened from', () {
      // Windows is $14.99 on the website and macOS $19.99. The page defaults
      // to Windows and otherwise sniffs the browser, so the OS has to be
      // named in the link rather than left to be guessed.
      expect(directUrlFor(apple: true).queryParameters['platform'], 'macos');
      expect(
          directUrlFor(apple: false).queryParameters['platform'], 'windows');
    });

    test('both are tagged as coming from the app', () {
      // Untagged, an arrival on /buy/ from the app is indistinguishable from
      // someone clicking "Pricing" on the website, so the app's own share of
      // that traffic cannot be told apart from the site's.
      for (final apple in [true, false]) {
        final url = directUrlFor(apple: apple);
        expect(url.queryParameters['utm_source'], 'app',
            reason: 'apple host: $apple');
        expect(url.queryParameters['utm_medium'], apple ? 'macos' : 'windows');
      }
    });

    test('both ask for the canonical /buy/ path over https', () {
      // The site exports every route as `<route>/index.html` and answers
      // `/buy` with a redirect; asking for the slash saves the hop.
      for (final apple in [true, false]) {
        final url = directUrlFor(apple: apple);
        expect(url.scheme, 'https');
        expect(url.host, 'wslmanager.com');
        expect(url.path, '/buy/');
      }
    });
  });

  group('copy keys', () {
    test('every key a route names has an English string', () {
      // A missing key renders as the raw key in the UI rather than failing,
      // so nothing else would catch a typo here.
      final en = englishStrings();

      for (final apple in [true, false]) {
        for (final route in purchaseRoutesFor(apple: apple)) {
          for (final key in [
            route.titleKey,
            route.detailKey,
            route.priceKey,
            route.buttonKey,
          ]) {
            expect(en.containsKey(key), true,
                reason: 'lib/i18n/en.json has no "$key"');
          }
        }
      }
    });

    test('the key-entry blurb only promises the automatic handover where the '
        'scheme is registered', () {
      final en = englishStrings();
      final mac = activateDetailKeyFor(apple: true);
      final windows = activateDetailKeyFor(apple: false);

      expect(mac, isNot(windows));
      expect(en.containsKey(mac), true);
      expect(en.containsKey(windows), true);
      // Only the Mac runner hands the key over through `wslmanager://`.
      expect(en[windows], isNot(contains('automatic')));
    });
  });
}
