#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PACKAGE_DIR="$REPO_DIR/apps/macos/NixMeApp"
OUTPUT_DIR="$REPO_DIR/build"
APP_BUNDLE="$OUTPUT_DIR/Nix Me.app"
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
APP_ICON_SOURCE="$PACKAGE_DIR/App/AppIcon.png"
APP_ICONSET="$OUTPUT_DIR/NixMe.iconset"
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

rust_targets=()
for arch in $NIX_ME_ARCHS; do
  case "$arch" in
    arm64)
      rust_targets+=(aarch64-apple-darwin)
      ;;
    x86_64)
      rust_targets+=(x86_64-apple-darwin)
      ;;
    *)
      echo "Unsupported macOS architecture for app-state engine: $arch" >&2
      exit 64
      ;;
  esac
done

rustup target add "${rust_targets[@]}"
rust_binaries=()
for target in "${rust_targets[@]}"; do
  cargo build \
    --manifest-path "$REPO_DIR/packages/app-state/engine/nix-me-apps/Cargo.toml" \
    --release \
    --target "$target"
  rust_binaries+=("$REPO_DIR/packages/app-state/engine/target/$target/release/nix-me-apps")
done

mkdir -p "$OUTPUT_DIR"
APP_STATE_ENGINE="$OUTPUT_DIR/nix-me-apps"
if [[ ${#rust_binaries[@]} -eq 1 ]]; then
  cp "${rust_binaries[0]}" "$APP_STATE_ENGINE"
else
  lipo -create "${rust_binaries[@]}" -output "$APP_STATE_ENGINE"
fi

if [[ -d "$APP_BUNDLE" ]]; then
  rm -rf -- "$APP_BUNDLE"
fi

mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources" "$APP_BUNDLE/Contents/Frameworks"
cp "$BIN_DIR/NixMeApp" "$APP_BUNDLE/Contents/MacOS/NixMeApp"
cp "$PACKAGE_DIR/App/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

if [[ ! -f "$APP_ICON_SOURCE" ]]; then
  echo "Missing macOS app icon source: $APP_ICON_SOURCE" >&2
  exit 66
fi
rm -rf -- "$APP_ICONSET"
mkdir -p "$APP_ICONSET"
while read -r filename size; do
  sips -z "$size" "$size" "$APP_ICON_SOURCE" --out "$APP_ICONSET/$filename" >/dev/null
done <<'EOF'
icon_16x16.png 16
icon_16x16@2x.png 32
icon_32x32.png 32
icon_32x32@2x.png 64
icon_128x128.png 128
icon_128x128@2x.png 256
icon_256x256.png 256
icon_256x256@2x.png 512
icon_512x512.png 512
icon_512x512@2x.png 1024
EOF
iconutil -c icns "$APP_ICONSET" -o "$APP_BUNDLE/Contents/Resources/NixMe.icns"
rm -rf -- "$APP_ICONSET"

mkdir -p "$APP_BUNDLE/Contents/Resources/management-api"
install -m 0755 \
  "$REPO_DIR/packages/management-api/bin/nix-me-api" \
  "$REPO_DIR/packages/management-api/bin/nix-me-action" \
  "$REPO_DIR/packages/management-api/bin/nix-me-details" \
  "$APP_BUNDLE/Contents/Resources/management-api/"
install -m 0755 "$APP_STATE_ENGINE" "$APP_BUNDLE/Contents/Resources/management-api/nix-me-apps"
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
