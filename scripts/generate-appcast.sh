#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION="${1:-}"
DMG_PATH="${2:-}"
OUTPUT_DIR="${3:-$REPO_DIR/dist}"
SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-com.nix-me.manager}"
SPARKLE_PRIVATE_KEY="${SPARKLE_PRIVATE_KEY:-}"
SPARKLE_PRIVATE_KEY_PATH="${SPARKLE_PRIVATE_KEY_PATH:-}"
TAG="v$VERSION"
ARCHIVE_DIR="$OUTPUT_DIR/sparkle"
GENERATE_APPCAST="$REPO_DIR/macos/NixMeApp/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"

if [[ -z "$VERSION" || ! -f "$DMG_PATH" ]]; then
  echo "Usage: $0 VERSION /path/to/Nix-Me-VERSION.dmg [output-directory]" >&2
  exit 64
fi

if [[ ! -x "$GENERATE_APPCAST" ]]; then
  echo "Sparkle tools are unavailable. Build the app first." >&2
  exit 69
fi

rm -rf "$ARCHIVE_DIR"
mkdir -p "$ARCHIVE_DIR" "$OUTPUT_DIR"
cp "$DMG_PATH" "$ARCHIVE_DIR/"

appcast_args=(
  --account "$SPARKLE_ACCOUNT"
  --download-url-prefix "https://github.com/lucamaraschi/nix-me/releases/download/$TAG/"
  -o "$ARCHIVE_DIR/appcast.xml"
)

if [[ -n "$SPARKLE_PRIVATE_KEY" ]]; then
  printf '%s' "$SPARKLE_PRIVATE_KEY" \
    | "$GENERATE_APPCAST" "${appcast_args[@]}" --ed-key-file - "$ARCHIVE_DIR"
elif [[ -n "$SPARKLE_PRIVATE_KEY_PATH" ]]; then
  "$GENERATE_APPCAST" "${appcast_args[@]}" --ed-key-file "$SPARKLE_PRIVATE_KEY_PATH" "$ARCHIVE_DIR"
else
  "$GENERATE_APPCAST" "${appcast_args[@]}" "$ARCHIVE_DIR"
fi

cp "$ARCHIVE_DIR/appcast.xml" "$OUTPUT_DIR/appcast.xml"
echo "Generated $OUTPUT_DIR/appcast.xml"
