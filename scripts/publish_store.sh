#!/usr/bin/env bash
# Publishes an MSIX to the Microsoft Store through the legacy submission API,
# and refuses whenever that API cannot carry the app's pricing unchanged.
#
# The API (manage.devcenter.microsoft.com/v1.0) predates Partner Center's
# market groups. For an app priced by market groups it returns
# `pricing.priceId: "Base"` and no market overrides — not "tier not set", but
# "this model cannot express what Partner Center holds". The whole object has
# to go back on PUT ("Pricing data was not provided" otherwise), and a PUT
# that carries "Base" is rejected. On 2026-09-07 this script answered that by
# deleting priceId and sending the rest; the API accepted a pricing object
# with no base tier and no overrides and published WSL Manager as FREE in all
# 240 markets, every market group gone (2.0.1 submission …31420, then 2.0.2
# as Submission 72). The comment that used to sit here — "the prices already
# sit on it server-side and stay exactly as they were" — was wrong.
#
# So: when the clone comes back with "Base", stop. The package then has to be
# updated by hand in Partner Center, where the pricing is left alone. When the
# clone carries a real tier, the object round-trips and publishing is safe.
#
# It also no longer deletes a pending submission it finds. On 2026-09-08 the
# one it deleted was the previous release, still in certification.
#
# Required environment:
#   STORE_TENANT_ID  STORE_CLIENT_ID  STORE_CLIENT_SECRET  STORE_APP_ID
# Argument:
#   $1  path to the .msix to publish
set -euo pipefail

MSIX_PATH="${1:?usage: publish_store.sh <path-to-msix>}"
[ -f "$MSIX_PATH" ] || { echo "No such package: $MSIX_PATH" >&2; exit 1; }

for var in STORE_TENANT_ID STORE_CLIENT_ID STORE_CLIENT_SECRET STORE_APP_ID; do
  [ -n "${!var:-}" ] || { echo "$var is not set" >&2; exit 1; }
done

API="https://manage.devcenter.microsoft.com/v1.0/my/applications"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# curl wrapper that keeps the body and the status code apart, so a failure
# reports what the API actually said instead of an empty string.
request() {
  local method="$1" url="$2" body="${3:-}"
  local args=(-sS -X "$method" -H "Authorization: Bearer $TOKEN"
              -o "$WORK/body" -w '%{http_code}')
  if [ -n "$body" ]; then
    args+=(-H "Content-Type: application/json" -d "$body")
  else
    args+=(-H "Content-Length: 0")
  fi
  local code
  code=$(curl "${args[@]}" "$url")
  cat "$WORK/body"
  [[ "$code" =~ ^2 ]] || {
    # Callers that only want the status discard stdout, so the API's own
    # explanation has to reach the log by another route.
    echo "$method $url -> HTTP $code" >&2
    cat "$WORK/body" >&2; echo >&2
    return 1
  }
}

echo "Authenticating..."
TOKEN=$(curl -sS -X POST "https://login.microsoftonline.com/$STORE_TENANT_ID/oauth2/token" \
  -d grant_type=client_credentials \
  --data-urlencode "client_id=$STORE_CLIENT_ID" \
  --data-urlencode "client_secret=$STORE_CLIENT_SECRET" \
  --data-urlencode "resource=https://manage.devcenter.microsoft.com" \
  | jq -r '.access_token // empty')
[ -n "$TOKEN" ] || { echo "Could not obtain an access token" >&2; exit 1; }

# A pending submission is not ours to remove: it may be the previous release
# still in certification, or a draft somebody is editing in Partner Center.
# Whoever owns it decides; this run just says so and stops.
PENDING=$(request GET "$API/$STORE_APP_ID" | jq -r '.pendingApplicationSubmission.id // empty')
if [ -n "$PENDING" ]; then
  echo "Submission $PENDING is pending (in certification, or a Partner Center draft)." >&2
  echo "Not deleting it. Let it finish or remove it by hand, then re-run." >&2
  echo "https://partner.microsoft.com/dashboard/products/$STORE_APP_ID/submissions/$PENDING" >&2
  exit 1
fi

echo "Creating submission..."
SUBMISSION=$(request POST "$API/$STORE_APP_ID/submissions")
SUBMISSION_ID=$(jq -r '.id' <<<"$SUBMISSION")
UPLOAD_URL=$(jq -r '.fileUploadUrl' <<<"$SUBMISSION")
[ -n "$SUBMISSION_ID" ] && [ "$SUBMISSION_ID" != "null" ] || {
  echo "The API returned no submission id" >&2; exit 1; }

# From here on a failure would strand a pending submission, so clean it up.
cleanup_submission() {
  echo "Removing the half-finished submission $SUBMISSION_ID..." >&2
  request DELETE "$API/$STORE_APP_ID/submissions/$SUBMISSION_ID" >/dev/null 2>&1 || true
}
trap 'cleanup_submission; rm -rf "$WORK"' EXIT

MSIX_NAME="$(basename "$MSIX_PATH")"

# The one check that matters. "Base" means the API could not read the pricing
# out of Partner Center, so nothing this script sends can put it back; the
# only pricing a PUT can preserve is one the clone states in full.
PRICE_ID=$(jq -r '.pricing.priceId // empty' <<<"$SUBMISSION")
if [ -z "$PRICE_ID" ] || [ "$PRICE_ID" = "Base" ]; then
  cat >&2 <<EOF
Refusing to publish: the submission API reports the base price as "${PRICE_ID:-<none>}".
That is what it returns when pricing is set by market groups in Partner Center,
which this API cannot express. Publishing through it would replace the pricing
with Free in every market (as happened on 2026-09-07/08).
Update the package by hand in Partner Center instead — pricing stays untouched there:
https://partner.microsoft.com/dashboard/products/$STORE_APP_ID/overview
EOF
  exit 1
fi

echo "Replacing the packages with $MSIX_NAME (base price tier $PRICE_ID, sent back unchanged)..."
BODY=$(jq --arg name "$MSIX_NAME" '
  .applicationPackages = (
      [ (.applicationPackages // [])[] | .fileStatus = "PendingDelete" ]
      + [ { fileName: $name,
            fileStatus: "PendingUpload",
            minimumDirectXVersion: "None",
            minimumSystemRam: "None" } ]
    )
' <<<"$SUBMISSION")

# Belt and braces: the pricing block must leave exactly as it arrived.
[ "$(jq -c .pricing <<<"$BODY")" = "$(jq -c .pricing <<<"$SUBMISSION")" ] \
  || { echo "Refusing to send a body whose pricing differs from the clone" >&2; exit 1; }

request PUT "$API/$STORE_APP_ID/submissions/$SUBMISSION_ID" "$BODY" >/dev/null

echo "Uploading the package..."
( cd "$(dirname "$MSIX_PATH")" && zip -q -j "$WORK/package.zip" "$MSIX_NAME" )
UPLOAD_CODE=$(curl -sS -X PUT -H "x-ms-blob-type: BlockBlob" \
  --data-binary "@$WORK/package.zip" -o /dev/null -w '%{http_code}' "$UPLOAD_URL")
[[ "$UPLOAD_CODE" =~ ^2 ]] || { echo "Package upload -> HTTP $UPLOAD_CODE" >&2; exit 1; }

echo "Committing..."
COMMIT=$(request POST "$API/$STORE_APP_ID/submissions/$SUBMISSION_ID/commit")
STATUS=$(jq -r '.status // "unknown"' <<<"$COMMIT")
echo "Submission $SUBMISSION_ID is now $STATUS."

# Committed: the submission belongs to Partner Center now, not to the trap.
trap 'rm -rf "$WORK"' EXIT

case "$STATUS" in
  CommitStarted|PendingPublication|Publishing|Published) ;;
  *) echo "Unexpected status after commit: $STATUS" >&2; exit 1 ;;
esac

echo "https://partner.microsoft.com/dashboard/products/$STORE_APP_ID/submissions/$SUBMISSION_ID"
