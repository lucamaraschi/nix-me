#!/bin/bash

set -euo pipefail

ARTIFACT="${1:-}"
APPLE_API_KEY_ID="${APPLE_API_KEY_ID:-}"
APPLE_API_ISSUER_ID="${APPLE_API_ISSUER_ID:-}"
APPLE_API_PRIVATE_KEY_PATH="${APPLE_API_PRIVATE_KEY_PATH:-}"
APPLE_API_PRIVATE_KEY_BASE64="${APPLE_API_PRIVATE_KEY_BASE64:-}"
TEMP_KEY=""

cleanup() {
  if [[ -n "$TEMP_KEY" ]]; then
    rm -f "$TEMP_KEY"
  fi
}
trap cleanup EXIT

if [[ -z "$ARTIFACT" || ! -f "$ARTIFACT" ]]; then
  echo "Usage: $0 /path/to/notarizable.dmg" >&2
  exit 64
fi

if [[ -z "$APPLE_API_KEY_ID" || -z "$APPLE_API_ISSUER_ID" ]]; then
  echo "APPLE_API_KEY_ID and APPLE_API_ISSUER_ID are required" >&2
  exit 64
fi

if [[ -z "$APPLE_API_PRIVATE_KEY_PATH" ]]; then
  if [[ -z "$APPLE_API_PRIVATE_KEY_BASE64" ]]; then
    echo "Set APPLE_API_PRIVATE_KEY_PATH or APPLE_API_PRIVATE_KEY_BASE64" >&2
    exit 64
  fi
  TEMP_KEY="$(mktemp "${TMPDIR:-/tmp}/AuthKey.XXXXXX.p8")"
  printf '%s' "$APPLE_API_PRIVATE_KEY_BASE64" | base64 -D >"$TEMP_KEY"
  chmod 600 "$TEMP_KEY"
  APPLE_API_PRIVATE_KEY_PATH="$TEMP_KEY"
fi

xcrun notarytool submit "$ARTIFACT" \
  --key "$APPLE_API_PRIVATE_KEY_PATH" \
  --key-id "$APPLE_API_KEY_ID" \
  --issuer "$APPLE_API_ISSUER_ID" \
  --wait

xcrun stapler staple "$ARTIFACT"
xcrun stapler validate "$ARTIFACT"
spctl --assess --type open --context context:primary-signature --verbose=2 "$ARTIFACT"

echo "Notarized and stapled $ARTIFACT"
