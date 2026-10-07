#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CLI="$REPO_DIR/apps/cli/bin/nix-me"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nix-me-harness-cli-test.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

cat >"$TEMP_DIR/fake-api" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$FAKE_API_LOG"
cat "$FAKE_API_RESPONSE"
SH
chmod +x "$TEMP_DIR/fake-api"

strip_color() {
    perl -pe 's/\e\[[0-9;]*m//g' "$1"
}

export NIX_ME_API_BIN="$TEMP_DIR/fake-api"
export FAKE_API_LOG="$TEMP_DIR/api.log"
export FAKE_API_RESPONSE="$FIXTURES_DIR/app-state-status.json"

"$CLI" harness status >"$TEMP_DIR/status-color.txt"
strip_color "$TEMP_DIR/status-color.txt" >"$TEMP_DIR/status.txt"

grep -q '^app-state$' "$FAKE_API_LOG"
grep -q 'Availability: Available' "$TEMP_DIR/status.txt"
grep -q 'Version: 0.1.0' "$TEMP_DIR/status.txt"
grep -q 'Configured recipes: 4' "$TEMP_DIR/status.txt"
grep -q 'Verified recipes: 1' "$TEMP_DIR/status.txt"
grep -q 'Unverified recipes: 3' "$TEMP_DIR/status.txt"
grep -q 'Configuration drift: 2' "$TEMP_DIR/status.txt"
grep -q 'Manual residue: 1' "$TEMP_DIR/status.txt"
grep -q 'Result: Succeeded' "$TEMP_DIR/status.txt"
grep -q 'Time: 2026-10-05T17:56:00Z' "$TEMP_DIR/status.txt"
grep -q 'Message: Applied 4 configured recipes' "$TEMP_DIR/status.txt"
grep -q 'One recipe needs review' "$TEMP_DIR/status.txt"

for apply_status in partial failed; do
    jq --arg status "$apply_status" '.appState.lastApply.status = $status' \
        "$FIXTURES_DIR/app-state-status.json" >"$TEMP_DIR/app-state-$apply_status.json"
    export FAKE_API_RESPONSE="$TEMP_DIR/app-state-$apply_status.json"
    "$CLI" harness status >"$TEMP_DIR/$apply_status-color.txt"
    strip_color "$TEMP_DIR/$apply_status-color.txt" >"$TEMP_DIR/$apply_status.txt"
done
grep -q 'Result: Partially succeeded' "$TEMP_DIR/partial.txt"
grep -q 'Result: Failed' "$TEMP_DIR/failed.txt"

: >"$FAKE_API_LOG"
export FAKE_API_RESPONSE="$FIXTURES_DIR/app-state-status.json"
"$CLI" harness diff >"$TEMP_DIR/diff-color.txt"
strip_color "$TEMP_DIR/diff-color.txt" >"$TEMP_DIR/diff.txt"
grep -q '^app-state$' "$FAKE_API_LOG"
grep -q 'Application State Diff' "$TEMP_DIR/diff.txt"
grep -q 'Harness differences detected' "$TEMP_DIR/diff.txt"

jq '
  .appState.driftCount = 0
  | .appState.manualResidueCount = 0
  | .appState.warnings = []
' "$FIXTURES_DIR/app-state-status.json" >"$TEMP_DIR/app-state-current.json"
export FAKE_API_RESPONSE="$TEMP_DIR/app-state-current.json"
"$CLI" harness diff >"$TEMP_DIR/current-color.txt"
strip_color "$TEMP_DIR/current-color.txt" >"$TEMP_DIR/current.txt"
grep -q 'Configuration drift: 0' "$TEMP_DIR/current.txt"
grep -q 'Manual residue: 0' "$TEMP_DIR/current.txt"
grep -q 'No drift or manual residue detected' "$TEMP_DIR/current.txt"

export FAKE_API_RESPONSE="$FIXTURES_DIR/app-state-unavailable.json"
"$CLI" harness status >"$TEMP_DIR/unavailable-color.txt"
strip_color "$TEMP_DIR/unavailable-color.txt" >"$TEMP_DIR/unavailable.txt"
grep -q 'Availability: Unavailable' "$TEMP_DIR/unavailable.txt"
grep -q 'Configured recipes: Unavailable' "$TEMP_DIR/unavailable.txt"
grep -q 'Configuration drift: Unavailable' "$TEMP_DIR/unavailable.txt"
grep -q 'Manual residue: Unavailable' "$TEMP_DIR/unavailable.txt"
grep -q 'Result: Unavailable' "$TEMP_DIR/unavailable.txt"
if grep -q 'Configuration drift: 0' "$TEMP_DIR/unavailable.txt"; then
    echo "Unavailable drift was rendered as zero" >&2
    exit 1
fi

if "$CLI" harness mutate >"$TEMP_DIR/invalid.txt" 2>&1; then
    echo "Unknown harness command unexpectedly succeeded" >&2
    exit 1
else
    invalid_status=$?
fi
[[ "$invalid_status" == 64 ]]

cat >"$TEMP_DIR/nix-me-apps" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >"$FAKE_APPS_LOG"
SH
chmod +x "$TEMP_DIR/nix-me-apps"
export FAKE_APPS_LOG="$TEMP_DIR/apps.log"
PATH="$TEMP_DIR:$PATH" "$CLI" apps diff --json
grep -q '^diff --json$' "$FAKE_APPS_LOG"

echo "nix-me harness CLI tests passed"
