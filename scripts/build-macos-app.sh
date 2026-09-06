#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PACKAGE_DIR="$REPO_DIR/macos/NixMeApp"
OUTPUT_DIR="$REPO_DIR/build"
APP_BUNDLE="$OUTPUT_DIR/Nix Me.app"
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
APP_VERSION="${APP_VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
NIX_ME_ARCHS="${NIX_ME_ARCHS:-$(uname -m)}"

build_args=(--package-path "$PACKAGE_DIR" --configuration release)
for arch in $NIX_ME_ARCHS; do
  build_args+=(--arch "$arch")
done

swift build "${build_args[@]}"
BIN_DIR="$(swift build "${build_args[@]}" --show-bin-path)"

if [[ -d "$APP_BUNDLE" ]]; then
  rm -rf -- "$APP_BUNDLE"
fi

mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources" "$APP_BUNDLE/Contents/Frameworks"
cp "$BIN_DIR/NixMeApp" "$APP_BUNDLE/Contents/MacOS/NixMeApp"
cp "$PACKAGE_DIR/App/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
ditto "$BIN_DIR/Sparkle.framework" "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BUNDLE/Contents/MacOS/NixMeApp"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$INFO_PLIST"

plutil -lint "$INFO_PLIST" >/dev/null

if [[ "$CODE_SIGN_IDENTITY" == "-" ]]; then
  codesign --force --sign - "$APP_BUNDLE" >/dev/null
else
  sparkle="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
  sign_args=(--force --sign "$CODE_SIGN_IDENTITY" --options runtime --timestamp)

  codesign "${sign_args[@]}" "$sparkle/Versions/B/XPCServices/Installer.xpc"
  codesign "${sign_args[@]}" --preserve-metadata=entitlements "$sparkle/Versions/B/XPCServices/Downloader.xpc"
  codesign "${sign_args[@]}" "$sparkle/Versions/B/Autoupdate"
  codesign "${sign_args[@]}" "$sparkle/Versions/B/Updater.app"
  codesign "${sign_args[@]}" "$sparkle"
  codesign "${sign_args[@]}" "$APP_BUNDLE"
fi

codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

echo "Built $APP_BUNDLE"
