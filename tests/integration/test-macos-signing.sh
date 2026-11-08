#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/bin" "$scratch/home"
export HOME="$scratch/home" PATH="$scratch/bin:$PATH"
export NIX_ME_SIGNING_IDENTITY_FILE="$scratch/pin"
export SIGNING_FIXTURE="$scratch/identities" SIGNING_LOG="$scratch/signing.log"
unset CODE_SIGN_IDENTITY NIX_ME_REQUIRE_STABLE_SIGNING
signer="$ROOT/tools/release/sign-macos-app.sh"
a=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
b=BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB
c=CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC
cat > "$scratch/bin/security" <<'EOF'
#!/bin/bash
[[ "$*" == 'find-identity -v -p codesigning' ]] || exit 70
cat "$SIGNING_FIXTURE"
EOF
cat > "$scratch/bin/codesign" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$SIGNING_LOG"
[[ "${FAIL_SIGNING:-0}" != 1 ]]
EOF
chmod +x "$scratch/bin/security" "$scratch/bin/codesign"
printf '  2) %s "Apple Development: Test (TEAM)"\n  1) %s "Developer ID Application: Test (TEAM)"\n' "$b" "$a" > "$SIGNING_FIXTURE"
[[ "$(bash "$signer" --resolve)" == "$a" ]]
[[ ! -f "$NIX_ME_SIGNING_IDENTITY_FILE" ]]
printf '%s\n' "$b" > "$NIX_ME_SIGNING_IDENTITY_FILE"
[[ "$(bash "$signer" --resolve)" == "$b" ]]
[[ "$(CODE_SIGN_IDENTITY="$a" bash "$signer" --resolve)" == "$a" ]]
[[ "$(CODE_SIGN_IDENTITY='Apple Development: Test (TEAM)' bash "$signer" --resolve)" == "$b" ]]
printf '%s\n' "$c" > "$NIX_ME_SIGNING_IDENTITY_FILE"
if bash "$signer" --resolve > "$scratch/out" 2>&1; then echo 'Missing pin must fail' >&2; exit 1; fi
grep -q 'Refusing to silently change' "$scratch/out"
rm "$NIX_ME_SIGNING_IDENTITY_FILE"
printf '0 valid identities found\n' > "$SIGNING_FIXTURE"
[[ "$(bash "$signer" --resolve 2> "$scratch/warning")" == - ]]
grep -q 'WARNING' "$scratch/warning"
if NIX_ME_REQUIRE_STABLE_SIGNING=1 bash "$signer" --resolve > "$scratch/out" 2>&1; then exit 1; fi
if CODE_SIGN_IDENTITY=- NIX_ME_REQUIRE_STABLE_SIGNING=1 bash "$signer" --resolve > "$scratch/out" 2>&1; then exit 1; fi
[[ "$(CODE_SIGN_IDENTITY=- bash "$signer" --resolve)" == - ]]
printf '  1) %s "Apple Development: Test (TEAM)"\n' "$b" > "$SIGNING_FIXTURE"
[[ "$(bash "$signer" --resolve)" == "$b" ]]

if [[ -x /usr/libexec/PlistBuddy ]]; then
  app="$scratch/Nix Me.app"
  mkdir -p "$app/Contents/Resources/management-api"
  /usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string com.nix-me.manager' "$app/Contents/Info.plist" >/dev/null
  touch "$app/Contents/Resources/management-api/nix-me-apps"
  if FAIL_SIGNING=1 bash "$signer" "$app"; then exit 1; fi
  [[ ! -f "$NIX_ME_SIGNING_IDENTITY_FILE" ]]
  NIX_ME_SIGNING_TIMESTAMP=none bash "$signer" "$app"
  [[ "$(<"$NIX_ME_SIGNING_IDENTITY_FILE")" == "$b" ]]
  grep -q -- '--identifier com.nix-me.manager.app-state' "$SIGNING_LOG"
  grep -q -- '--verify --deep --strict' "$SIGNING_LOG"
  grep -q -- '--timestamp=none' "$SIGNING_LOG"
fi
printf '%s\n' 'macOS signing tests passed'
