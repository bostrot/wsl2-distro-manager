#!/usr/bin/env bash
# Publishes an MSIX to the Microsoft Store without touching pricing.
#
# The obvious choice, isaacrlevin/windows-store-action, reads the cloned
# submission and PUTs the whole object back, `pricing` included. Partner
# Center reports this app's base price as "Base" — the "price tier is not
# set" placeholder — and the API rejects on write what it just emitted on
# read: "'Base' is not a valid PriceId for base price". The action has no
# input to leave that section alone, so this script does the same calls but
# never sends a base price id. The submission is a clone of the published
# one, so the prices already sit on it server-side and stay exactly as they
# were.
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

# A submission left pending by an earlier failed run blocks the next one, and
# blocks editing the app in Partner Center.
PENDING=$(request GET "$API/$STORE_APP_ID" | jq -r '.pendingApplicationSubmission.id // empty')
if [ -n "$PENDING" ]; then
  echo "Deleting the submission left pending by an earlier run ($PENDING)..."
  request DELETE "$API/$STORE_APP_ID/submissions/$PENDING" >/dev/null
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
echo "Replacing the packages with $MSIX_NAME, leaving pricing untouched..."

# Dropping the base-price id is the entire point of this script. The API
# insists on a pricing object ("Pricing data was not provided"), so the rest
# of it goes back exactly as the clone provided it; only the "Base"
# placeholder it will not accept is left out, and the server keeps the base
# price it already holds.
BODY=$(jq --arg name "$MSIX_NAME" '
  del(.pricing.priceId)
  | .applicationPackages = (
      [ (.applicationPackages // [])[] | .fileStatus = "PendingDelete" ]
      + [ { fileName: $name,
            fileStatus: "PendingUpload",
            minimumDirectXVersion: "None",
            minimumSystemRam: "None" } ]
    )
' <<<"$SUBMISSION")

jq -e '.pricing | has("priceId") | not' <<<"$BODY" >/dev/null \
  || { echo "Refusing to send a body that still carries a base price id" >&2; exit 1; }

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
