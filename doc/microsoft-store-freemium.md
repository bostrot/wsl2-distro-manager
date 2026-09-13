# Making the Microsoft Store listing free

WSL Manager has always been a paid app on the Microsoft Store, and on Windows
that purchase *is* the licence: the app asks whether it has MSIX package
identity and, if it does, unlocks Pro. The website sells a licence key
instead, which is how macOS has always worked and how a Windows buyer who
would rather avoid the Store can buy today.

This document is the answer to "what would it take to make the Store listing
free and sell Pro through Stripe everywhere, without taking Pro away from
anyone who already bought it in the Store".

Short version: it takes one build, one price change, and no server. Both are
in 2.2.0: `storeFreeFromUtc` names the instant (2026-09-13 00:00 UTC), and
the release that carries it also publishes `store/pricing.json`, which now
says Free — one workflow run does both.

## The one hard problem

Everything else is routine. This is not:

> Once the listing is free, the Store tells the app nothing that separates
> "bought this for $9.99 in 2024" from "downloaded this for nothing today".

`StoreContext.GetAppLicenseAsync()` reports `IsActive: true` for both, and
`PurchaseDate` is populated for both. Microsoft has no "grandfather my
existing buyers" feature, and there is no bulk way to grant an add-on to
everyone who bought the app before a given date.

The second constraint is Eric's, and it rules out the obvious workaround:

> "I would like to avoid a thing where we have to update our app first, then
> wait until users have the latest version, then make it freemium. That way
> will only work for users updating in a short timeframe."

Which is fair — a scheme that only protects people who happened to launch the
app during a particular week is not a scheme.

## What makes it solvable anyway

Two facts, neither obvious until you line them up:

1. **The Store only ever installs the newest build.** So a free download that
   happens after the flip always runs code that knows about the flip. The
   copies running *old* code are, without exception, copies that were
   installed while the app cost money — and old code grants them Pro through
   package identity, for ever, with no update required. The population that
   "never updates" is exactly the population that should keep Pro anyway.

2. **Every install already writes down which version it last ran.** The
   `version` preference has been set on first start since long before any of
   this (`lib/nav/init.dart`). An install that last ran 2.1.0 has only ever
   run a build from the paid era. A free download cannot be in that state,
   because free downloads do not exist before `storeFreemiumVersion`.

So the app can tell the two apart without asking Microsoft, without a backend,
and without a build that has to ship weeks in advance.

## The rule

`storeGrandfathers()` in `lib/api/license_manager.dart`, asked once per start,
in order:

| Case | Pro? | Why |
|---|---|---|
| Not an MSIX install | no | Portable build. Pro comes from a key, as always. |
| Already granted (`StoreProGrandfathered`) | yes | Decided on an earlier run. Never revisited. |
| No flip scheduled (`storeFreeFromUtc` is null) | yes | The paid era, and the rollback: the listing sells the app, so every Store install was paid for. |
| Now is before the flip | yes | This copy was bought while it cost money. |
| After the flip, last ran < `storeFreemiumVersion` | yes | Only ever ran a paid-era build. |
| Anything else | no | A free download. |

The last-ran-version row has one extra condition: the running build has to
know its own version. `currentVersion` is stamped in by the release workflow
and an unstamped build reports `1.0.0`, under which the *second* start of a
brand-new free install looks exactly like a copy from the paid era. A build
that cannot name itself declines to judge.

`storeFreeFromUtc` is read as UTC whether or not it says so. An ISO string
with no zone would otherwise be taken as the reader's local time, and the app
would flip at a different instant in every time zone while the listing flips
at one.

The first "yes" is written to `StoreProGrandfathered` and never recomputed.
That matters: the evidence is perishable. The flip instant passes, and the
`version` preference is overwritten on the very next start. A copy that was
bought has to keep Pro long after both have gone.

Note the ordering dependency this creates: `LicenseManager.init()` runs in
`main()` and reads `version` *before* `initRoot()` overwrites it. There is a
comment at both ends saying so.

### Where it leaks

**A legacy buyer who reinstalls on a new PC after the flip.** No preferences,
no stored flag, nothing local to go on — they land on Free. This is the one
real gap, and it is small (a minority event among a population that is itself
finite and shrinking), but it hits paying customers, so it needs an answer:

- *Now:* the licence screen's "Get help" link, and a key issued by hand
  through the same n8n licence service the website uses. The free-era copy
  (`win-activate-free-detail-text`, `restore-notfound-free-text`) says so in
  as many words, in all ten languages.
- *Later, if the volume justifies it:* see "The Store can actually answer
  this" below.

**Someone who edits the preferences file to fake an old version.** Yes. The
repo is open source and the README says so; neither the package-identity check
nor the licence key is protection, and this is not either. It is a nudge.

### The Store can actually answer this — at a price

`StoreContext.GetStoreProductForCurrentAppAsync()` returns a `StoreProduct`
whose `ExtendedJsonData` contains `Sku.CollectionData`, and that carries
`acquiredDate`, `skuType` ("Full" vs "Trial"), `status` and `orderId`. An
acquisition dated before the flip is a purchase; one after it is a free
download. It is undocumented-but-load-bearing JSON rather than a real API, and
it needs the user signed into the Store, but it is client-side only — no Azure
AD app, no backend, unlike the REST collection API, which needs both.

The cost is that `Windows.Services.Store` is WinRT: reaching it from this app
means a C++/WinRT call in `windows/runner` (a `StoreContext` from a Win32
process also has to be initialised with the window handle via
`IInitializeWithWindow`) behind a method channel or FFI export. That is real
work, it cannot be built or tested from the macOS dev host, and it is only
needed for the reinstall case. Hence: not now, documented here, worth doing if
support requests show up.

## What else changes in the app

Once the listing is free it sells nothing, so:

- **The Store card disappears from the licence screen** — on every Windows
  build, not just packaged ones. The portable build used to point at the Store
  as the cheaper of the two routes; after the flip that link goes to a page
  that cannot take the buyer's money. Windows is left with the same single
  website card the Mac shows, at the Windows price
  (`purchaseRoutesFor(storeSellsPro: false)`).
- **The copy stops promising that a Store copy unlocks itself**, which is the
  precise thing that has stopped being true for whoever is reading it.
- **"Store install" and "has Pro" stop being the same question.** A free Store
  copy is still a Store copy: the Store still updates it, and its owner can
  still post a review. `isStorePackaged` is now what the updater and the
  rating prompt ask; `isStoreLicensed` is the entitlement.

Selling Pro through Stripe inside a Store app is allowed. Microsoft Store
policy 10.8.1 lets non-game Windows apps use a third-party commerce engine for
in-app products, and purchases made through it are not subject to the Store
fee. (Games, and anything on Xbox, must use Microsoft's commerce engine —
neither applies here.) So there is no need for a Store add-on at all, and the
Windows buying experience becomes identical to the Mac one: same shop, same
key, same activation.

## The options that were considered

### A. One listing, flip it to free — recommended

What this document describes. Keeps the listing, its reviews, its rating and
its search ranking; needs one build and one price change; no second submission
pipeline; no backend.

### B. New free listing, hide the paid one

Eric's suggestion, and it does solve the grandfathering trivially: the paid
package keeps its own identity, so its buyers keep Pro through the existing
check with no new code at all. The costs are what make it second choice:

- **The reviews and the rating do not move.** They are attached to the product,
  and they are years of accumulated signal — the single most valuable thing the
  listing has, and the hardest to rebuild.
- **Two products to publish, for ever.** Existing buyers only keep getting
  updates if the old listing keeps getting submissions. "Available but not
  discoverable" keeps it reachable by direct link and keeps updates flowing;
  "stop acquisition" stops new purchases. Either way it is a second MSIX, a
  second certification queue and a second set of release notes on every
  release — plus the app then has to know which of the two it is.
- **Search ranking and install base restart at zero.**

Worth revisiting only if option A's flip turns out to be blocked in Partner
Center for a reason not visible from here.

### C. Free base app + paid "Pro" Store add-on

The textbook freemium shape, and it has the same grandfathering problem as A —
past buyers of the *app* do not own the *add-on* — so it needs the same
`ExtendedJsonData` check to be fair to them. It adds a second commerce path to
maintain (Store add-on on Windows, Stripe everywhere else), two prices to keep
in step, and the Store's fee on every Windows sale. Its one advantage is the
in-Store purchase flow, which is worth something on a touch-first device and
not much on a developer tool. Not recommended, and it is not what the issue
asks for ("offer the same buying experience over Stripe as non-store buys").

### D. Trial

Partner Center can put a time-limited or unlimited trial on a paid app. It
does not answer any part of this: the app stays paid, and the trial version
has the same "who is a buyer" problem the moment it stops being one.

## Rollout

The original plan had two shipping steps — land the gate switched off, then
pick an instant and ship again — so that the grandfathered population could
build up on its own before the price moved. It was collapsed into one release
on request: 2.2.0 carries the gate, the instant and the price change together.
Nothing is lost by that, because the copies that never see 2.2.0 keep Pro
through old code, and the copies that update to it are recognised by the
version they last ran.

1. **The build.** `storeFreeFromUtc` is `2026-09-13T00:00:00Z` and
   `storeFreemiumVersion` is `2.2.0`, the version in `pubspec.yaml`. The
   instant is deliberately *before* the release rather than after it: it only
   has to be no later than the moment the listing actually goes free, and
   that moment is when the 2.2.0 submission clears certification, which is
   days out and not a fixed length. An instant in the past costs nothing —
   every paid-era build is unaware of it, and the first build that is aware
   arrives with the price change — whereas an instant the certification
   overshot would have handed Pro to free downloads made in between.

2. **The price change.** `store/pricing.json` states `priceId: "Free"` with
   no market overrides, which is what clears the per-market tiers — a
   leftover override would keep Switzerland at $14.99 while the listing says
   free everywhere else. It is the file **Publish to Microsoft Store** states
   by default, so the release's own dispatch of that workflow makes the
   listing free with no further input; a `release` event states it too. The
   publisher's guard, which exists because a pricing object with no base tier
   once made the app free in all 240 markets by accident, accepts `Free` only
   when a file says it in as many words. The paid tiers moved to
   `store/pricing-paid.json`, which nothing publishes unless it is named.

   To prove the pricing before trusting the release to it, run the workflow
   by hand with `mode: dry-run` first; it creates a submission, writes the
   pricing, reads it back, reports, and deletes the submission.

3. **The website.** `/buy/` says the Windows app is a free download and that
   Pro is the licence key sold there; the Store comparison copy in the app
   (`store-price-text`, and the Store-vs-website framing) is handled by the
   route change.

4. **Watch.** `license` page views and `license_buy_clicked` (with
   `route: direct`) are already reported; after the flip the Store route stops
   appearing in that breakdown, which is itself the confirmation that the new
   build is the one people are running.

### Rolling back

Set `storeFreeFromUtc` back to null, ship, and run **Publish to Microsoft
Store** with `pricing_file: store/pricing-paid.json` (dry-run first).
Installs that were grandfathered stay grandfathered — the flag is never
cleared — and free downloads from the free window keep whatever they had. The
window is the cost of changing your mind.

## Sources

- [Microsoft Store Policies 10.8.1](https://learn.microsoft.com/en-us/windows/apps/publish/store-policies) — third-party commerce engines in non-game Windows apps
- [Set app pricing and availability](https://learn.microsoft.com/en-us/windows/apps/publish/publish-your-app/price-and-availability) — Free as a base price, scheduled price changes, visibility options
- [Manage app submissions](https://learn.microsoft.com/en-us/windows/uwp/monetize/manage-app-submissions) — `priceId: "Free"` in the submission API
- [Determining a previous purchase after going freemium](https://learn.microsoft.com/en-us/answers/questions/557066/in-case-i-changed-my-app-from-paid-to-freemium-how.html) — `ExtendedJsonData` / `CollectionData.acquiredDate`
- [Remove an app from the Store](https://learn.microsoft.com/en-us/windows/apps/publish/publish-your-app/remove-an-app-and-add-on) — existing customers keep an app that is no longer offered
