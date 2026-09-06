// The ways a user can buy Pro, and which of them a given host offers.
//
// Windows has two: the Microsoft Store listing the app has always had, and —
// for buyers who would rather not go through the Store at all — the same
// website shop the Mac uses, which sells a licence key instead. macOS has
// only the website, since there is no Store to sell through.
//
// The copy lives here as i18n keys rather than strings so the screen stays a
// plain renderer and the route set itself is testable without a UI.

import 'package:wsl2distromanager/components/constants.dart';

/// How a route is identified in the UI — used for widget test keys and to
/// tell the two cards apart.
enum PurchaseRouteId {
  /// The Microsoft Store listing. Being installed from it *is* the licence.
  store,

  /// wslmanager.com, which sells a licence key the user activates in-app.
  direct,
}

/// One way to buy Pro: where to send the buyer, and the copy describing it.
class PurchaseRoute {
  const PurchaseRoute({
    required this.id,
    required this.url,
    required this.titleKey,
    required this.detailKey,
    required this.priceKey,
    required this.buttonKey,
  });

  final PurchaseRouteId id;

  /// Opened in the user's browser (or the Store app) when they buy.
  final String url;

  final String titleKey;
  final String detailKey;
  final String priceKey;
  final String buttonKey;
}

/// The routes offered on this host, in the order they should be shown.
///
/// [apple] is `isAppleHost`, passed in rather than read here so the whole
/// set is testable from a Windows *or* a Mac test host.
List<PurchaseRoute> purchaseRoutesFor({required bool apple}) {
  const direct = PurchaseRoute(
    id: PurchaseRouteId.direct,
    url: macBuyUrl,
    // The website is the only route on the Mac, so it carries the plain
    // "Get Pro" heading there.
    titleKey: 'store-buy-title',
    detailKey: 'web-buy-detail-text',
    priceKey: 'web-price-text',
    buttonKey: 'web-buy-btn',
  );

  if (apple) return const [direct];

  return const [
    PurchaseRoute(
      id: PurchaseRouteId.store,
      url: windowsStoreUrl,
      titleKey: 'store-buy-title',
      detailKey: 'store-buy-detail-text',
      priceKey: 'store-price-text',
      buttonKey: 'store-buy-btn',
    ),
    // Second, and headed as the alternative it is: the Store stays the
    // cheaper, primary route on Windows.
    PurchaseRoute(
      id: PurchaseRouteId.direct,
      url: windowsBuyUrl,
      titleKey: 'web-buy-title',
      detailKey: 'win-web-buy-detail-text',
      priceKey: 'win-web-price-text',
      buttonKey: 'web-buy-btn',
    ),
  ];
}

/// The i18n key for the licence-key entry blurb. Only the Mac hands the key
/// over automatically after checkout, so only the Mac's copy says so.
String activateDetailKeyFor({required bool apple}) =>
    apple ? 'activate-detail-text' : 'win-activate-detail-text';
