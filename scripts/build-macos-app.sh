#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PACKAGE_DIR="$REPO_DIR/macos/NixMeApp"
OUTPUT_DIR="$REPO_DIR/build"
APP_BUNDLE="$OUTPUT_DIR/Nix Me.app"

swift build --package-path "$PACKAGE_DIR" --configuration release
BIN_DIR="$(swift build --package-path "$PACKAGE_DIR" --configuration release --show-bin-path)"

if [[ -d "$APP_BUNDLE" ]]; then
  rm -rf -- "$APP_BUNDLE"
fi

mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BIN_DIR/NixMeApp" "$APP_BUNDLE/Contents/MacOS/NixMeApp"
cp "$PACKAGE_DIR/App/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

plutil -lint "$APP_BUNDLE/Contents/Info.plist" >/dev/null
codesign --force --sign - "$APP_BUNDLE" >/dev/null

echo "Built $APP_BUNDLE"
