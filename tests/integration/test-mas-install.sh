#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nix-me-mas-test.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

cat >"$TEMP_DIR/manifest.json" <<'JSON'
{
  "software": {
    "homebrew": {
      "masApps": {
        "Alpha": 111,
        "Beta": 222,
        "Installed": 333
      }
    }
  }
}
JSON

cat >"$TEMP_DIR/mas" <<'SH'
#!/bin/bash
set -euo pipefail
state_dir="${NIX_ME_MAS_TEST_STATE:?}"
case "$1" in
  list)
    cat "$state_dir/installed"
    ;;
  install)
    printf 'install %s\n' "$2" >>"$state_dir/calls"
    if [[ "$2" == "222" || "$2" == "444" ]]; then
      exit 42
    fi
    printf '%s Test (1.0)\n' "$2" >>"$state_dir/installed"
    ;;
  get)
    printf 'get %s\n' "$2" >>"$state_dir/calls"
    if [[ "$2" == "444" ]]; then
      exit 43
    fi
    printf '%s Test (1.0)\n' "$2" >>"$state_dir/installed"
    ;;
  *) exit 64 ;;
esac
SH

cat >"$TEMP_DIR/timeout" <<'SH'
#!/bin/bash
shift 3
exec "$@"
SH

chmod +x "$TEMP_DIR/mas" "$TEMP_DIR/timeout"
printf '333 Installed (1.0)\n' >"$TEMP_DIR/installed"
: >"$TEMP_DIR/calls"

NIX_ME_MAS_BIN="$TEMP_DIR/mas" \
NIX_ME_TIMEOUT_BIN="$TEMP_DIR/timeout" \
NIX_ME_MAS_TEST_STATE="$TEMP_DIR" \
  "$REPO_DIR/packages/management-api/bin/nix-me-install-mas-apps" \
  "$TEMP_DIR/manifest.json" >"$TEMP_DIR/stdout" 2>"$TEMP_DIR/events"

cat >"$TEMP_DIR/expected-calls" <<'EOF'
install 111
install 222
get 222
EOF
cmp "$TEMP_DIR/expected-calls" "$TEMP_DIR/calls"
grep -Fq $'NIX_ME_PACKAGE\tmacAppStore\tinstalling\tAlpha\t' "$TEMP_DIR/events"
grep -Fq $'NIX_ME_PACKAGE\tmacAppStore\tcomplete\tAlpha\t' "$TEMP_DIR/events"
grep -Fq $'NIX_ME_PACKAGE\tmacAppStore\tinstalling\tBeta\t' "$TEMP_DIR/events"
grep -Fq $'NIX_ME_PACKAGE\tmacAppStore\tcomplete\tBeta\t' "$TEMP_DIR/events"
grep -Fq $'NIX_ME_PACKAGE\tmacAppStore\tcomplete\tInstalled\tAlready installed' "$TEMP_DIR/events"
grep -Fq $'NIX_ME_PROGRESS\tactivating\tMac App Store applications are ready' "$TEMP_DIR/events"

cat >"$TEMP_DIR/failing-manifest.json" <<'JSON'
{
  "software": {
    "homebrew": {
      "masApps": {
        "Blocked": 444
      }
    }
  }
}
JSON

: >"$TEMP_DIR/installed"
: >"$TEMP_DIR/calls"
set +e
NIX_ME_MAS_BIN="$TEMP_DIR/mas" \
NIX_ME_TIMEOUT_BIN="$TEMP_DIR/timeout" \
NIX_ME_MAS_TEST_STATE="$TEMP_DIR" \
  "$REPO_DIR/packages/management-api/bin/nix-me-install-mas-apps" \
  "$TEMP_DIR/failing-manifest.json" >"$TEMP_DIR/failing-stdout" 2>"$TEMP_DIR/failing-events"
failure_status=$?
set -e

if [[ "$failure_status" -eq 0 ]]; then
  echo "Expected a failed Mac App Store installation" >&2
  exit 1
fi
grep -Fq $'NIX_ME_PACKAGE\tmacAppStore\tfailed\tBlocked\t' "$TEMP_DIR/failing-events"
grep -Fq 'Open the App Store, sign in under the macOS user' "$TEMP_DIR/failing-events"

printf 'nix-me sequential Mac App Store installation passed\n'
