#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
APP_BUNDLE="${APP_BUNDLE:-$REPO_DIR/build/Nix Me.app}"
DIST_DIR="${DIST_DIR:-$REPO_DIR/dist}"
APP_VERSION="${APP_VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_BUNDLE/Contents/Info.plist")}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
DMG_PATH="$DIST_DIR/Nix-Me-$APP_VERSION.dmg"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nix-me-dmg.XXXXXX")"

cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "App bundle not found: $APP_BUNDLE" >&2
  exit 66
fi

mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH"
ditto "$APP_BUNDLE" "$STAGING_DIR/Nix Me.app"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
  -volname "Nix Me" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

if [[ "$CODE_SIGN_IDENTITY" != "-" ]]; then
  codesign --force --sign "$CODE_SIGN_IDENTITY" --timestamp "$DMG_PATH"
  codesign --verify --verbose=2 "$DMG_PATH"
fi

shasum -a 256 "$DMG_PATH" >"$DMG_PATH.sha256"
echo "Packaged $DMG_PATH"
