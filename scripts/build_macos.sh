#!/bin/bash
# Build the macOS app together with the vmctl virtualization helper.
#
# vmctl needs the com.apple.security.virtualization entitlement to run VMs,
# so it is signed explicitly (ad-hoc by default; set CODESIGN_IDENTITY for a
# real identity). The helper is copied into the app bundle's Resources so
# the app finds it next to itself; during `flutter run` it is picked up from
# ~/Library/Application Support/WSLManager/bin/vmctl or $VMCTL_PATH instead.
set -euo pipefail

cd "$(dirname "$0")/.."
IDENTITY="${CODESIGN_IDENTITY:--}"

echo "==> Building vmctl (release)"
(cd macos/vmctl && swift build -c release)
VMCTL_BIN=macos/vmctl/.build/release/vmctl

echo "==> Signing vmctl with virtualization entitlement"
codesign --force --sign "$IDENTITY" \
  --entitlements macos/vmctl/vmctl.entitlements \
  "$VMCTL_BIN"

if [[ "${VMCTL_ONLY:-0}" == "1" ]]; then
  echo "==> vmctl built at $VMCTL_BIN"
  exit 0
fi

echo "==> Building Flutter macOS app"
flutter build macos --release

APP=$(ls -d build/macos/Build/Products/Release/*.app | head -1)
echo "==> Bundling vmctl into $APP"
cp "$VMCTL_BIN" "$APP/Contents/Resources/vmctl"
codesign --force --sign "$IDENTITY" \
  --entitlements macos/vmctl/vmctl.entitlements \
  "$APP/Contents/Resources/vmctl"

# Re-seal the outer bundle after modifying its contents.
codesign --force --deep --sign "$IDENTITY" "$APP"
echo "==> Done: $APP"
