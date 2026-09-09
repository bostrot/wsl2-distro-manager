#!/usr/bin/env bash
# Offline check of scripts/store_pricing.jq against the shape the API
# actually returned for this app on 2026-09-07 (priceId "Base", two markets
# NotAvailable, advanced pricing model). No network, no credentials.
set -euo pipefail
cd "$(dirname "$0")/.."

CLONE='{"id":"1152921505701830657","pricing":{"trialPeriod":"NoFreeTrial","marketSpecificPricings":{"LB":"NotAvailable","EH":"NotAvailable","DE":"Tier1000"},"sales":[],"priceId":"Base","isAdvancedPricingModel":true},"visibility":"Public"}'
OUT=$(jq --from-file scripts/store_pricing.jq --argjson pricing "$(jq -c . store/pricing.json)" <<<"$CLONE")

check() {
  if jq -e "$2" <<<"$OUT" >/dev/null; then echo "ok   $1"; else echo "FAIL $1" >&2; jq .pricing <<<"$OUT" >&2; exit 1; fi
}
check "base tier comes from the file"                     '.pricing.priceId == "Tier1102"'
check "markets the clone cannot sell in stay unavailable" '.pricing.marketSpecificPricings.LB == "NotAvailable" and .pricing.marketSpecificPricings.EH == "NotAvailable"'
check "a stale clone override not in the file is dropped" '.pricing.marketSpecificPricings | has("DE") | not'
check "tier A market priced 14.99"                        '.pricing.marketSpecificPricings.CH == "Tier1112"'
check "tier C market priced 4.99"                         '.pricing.marketSpecificPricings.IN == "Tier1052"'
check "12 + 64 priced markets plus the 2 unavailable"     '(.pricing.marketSpecificPricings | length) == 78'
check "trial period, sales and model flag untouched"      '.pricing.trialPeriod == "NoFreeTrial" and .pricing.sales == [] and .pricing.isAdvancedPricingModel == true'
check "nothing outside pricing changed"                   '.id == "1152921505701830657" and .visibility == "Public"'
jq -e '.priceId | test("^Tier[0-9]+$")' store/pricing.json >/dev/null && echo "ok   file base tier is a Tier id"
jq -e '[.marketSpecificPricings[]] | all(test("^Tier[0-9]+$"))' store/pricing.json >/dev/null && echo "ok   every file override is a Tier id"
[ "$(jq '.marketSpecificPricings | length' store/pricing.json)" = "76" ] && echo "ok   file lists 76 markets"
echo "all store pricing checks passed"
