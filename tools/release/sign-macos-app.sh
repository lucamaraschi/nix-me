#!/bin/bash

set -euo pipefail

# Persist only the public certificate fingerprint, never a private key or TCC grant.
pin_file="${NIX_ME_SIGNING_IDENTITY_FILE:-$HOME/Library/Application Support/Nix Me/signing-identity}"
requested="${CODE_SIGN_IDENTITY:-auto}"
require_stable="${NIX_ME_REQUIRE_STABLE_SIGNING:-0}"

fail() { printf 'Nix Me signing: %s\n' "$*" >&2; exit 1; }

resolve_identity() {
  if [[ "$requested" == "-" ]]; then
    [[ "$require_stable" != 1 ]] || fail "Stable signing is required; ad-hoc signing was requested."
    printf '%s\n' -
    return
  fi

  local identities pinned selected
  identities="$(security find-identity -v -p codesigning)" || fail "Cannot inspect the signing keychain. Unlock it and retry."
  # Strip status and summary lines; exact names and SHA-1 fingerprints are accepted.
  identities="$(printf '%s\n' "$identities" | sed -nE 's/^[[:space:]]*[0-9]+\) ([0-9A-Fa-f]{40}) "([^"]+)"$/\1|\2/p' | LC_ALL=C sort)"
  if [[ "$requested" != auto ]]; then
    selected="$(printf '%s\n' "$identities" | awk -F '|' -v value="$requested" '$1 == toupper(value) || $2 == value { print $1 }')"
    [[ -n "$selected" && "$selected" != *$'\n'* ]] || fail "Requested identity is unavailable or ambiguous: $requested"
  elif [[ -f "$pin_file" ]]; then
    pinned="$(<"$pin_file")"
    [[ "$pinned" =~ ^[0-9A-Fa-f]{40}$ ]] || fail "Invalid identity pin at $pin_file. Select CODE_SIGN_IDENTITY explicitly to replace it."
    selected="$(printf '%s\n' "$identities" | awk -F '|' -v value="$pinned" '$1 == toupper(value) { print $1 }')"
    [[ -n "$selected" ]] || fail "The pinned certificate ($pinned) is unavailable. Unlock/import that identity, or deliberately select a replacement with CODE_SIGN_IDENTITY. Refusing to silently change the app identity."
  else
    selected="$(printf '%s\n' "$identities" | awk -F '|' '$2 ~ /^Developer ID Application:/ { print $1; exit }')"
    if [[ -z "$selected" ]]; then
      selected="$(printf '%s\n' "$identities" | awk -F '|' '$2 ~ /^Apple Development:/ { print $1; exit }')"
    fi
    if [[ -z "$selected" ]]; then
      [[ "$require_stable" != 1 ]] || fail "No Developer ID Application or Apple Development identity is available. Import a signing certificate and its private key, then retry."
      printf '%s\n' "Nix Me signing: WARNING: no signing certificate is available. Using ad-hoc signing; privacy approvals may need renewing after updates. No permissions or keychain trust settings were changed." >&2
      selected=-
    fi
  fi
  printf '%s\n' "$selected"
}

identity="$(resolve_identity)"
if [[ "${1:-}" == --resolve ]]; then
  printf '%s\n' "$identity"
  exit 0
fi
[[ $# -eq 1 && -d "$1/Contents" ]] || fail "Usage: sign-macos-app.sh APP_BUNDLE | --resolve"
app="$1"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")"
args=(--force --sign "$identity")
if [[ "$identity" == - ]]; then
  args+=(--timestamp=none)
else
  args+=(--options runtime)
  if [[ "${NIX_ME_SIGNING_TIMESTAMP:-auto}" == none ]]; then
    args+=(--timestamp=none)
  else
    args+=(--timestamp)
  fi
fi

engine="$app/Contents/Resources/management-api/nix-me-apps"
if [[ -f "$engine" ]]; then
  codesign "${args[@]}" --identifier "$bundle_id.app-state" "$engine"
fi
sparkle="$app/Contents/Frameworks/Sparkle.framework"
if [[ -d "$sparkle" && "$identity" != - ]]; then
  codesign "${args[@]}" "$sparkle/Versions/Current/XPCServices/Installer.xpc"
  codesign "${args[@]}" --preserve-metadata=entitlements "$sparkle/Versions/Current/XPCServices/Downloader.xpc"
  codesign "${args[@]}" "$sparkle/Versions/Current/Autoupdate"
  codesign "${args[@]}" "$sparkle/Versions/Current/Updater.app"
  codesign "${args[@]}" "$sparkle"
fi
codesign "${args[@]}" "$app"
codesign --verify --deep --strict --verbose=2 "$app"

if [[ "$identity" != - ]]; then
  # Update the pin only after a successful signature. Explicit selection is the rotation path.
  (umask 077; mkdir -p "$(dirname "$pin_file")"
    temporary="$(mktemp "$pin_file.XXXXXX")"
    trap 'rm -f "$temporary"' EXIT
    printf '%s\n' "$identity" > "$temporary"
    mv -f "$temporary" "$pin_file")
  printf 'Nix Me signing: certificate %s (pinned in %s)\n' "$identity" "$pin_file" >&2
fi
