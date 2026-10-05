#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nix-me-action-test.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

export NIX_ME_CONFIG_DIR="$REPO_DIR"
export NIX_ME_ACTION_DRY_RUN=1

"$REPO_DIR/bin/nix-me" action update >"$TEMP_DIR/result.json" <<'JSON'
{"items":[{"name":"nixpkgs","kind":"nixFlake","installedVersions":["old"],"availableVersion":"new"},{"name":"coreutils","kind":"formula","installedVersions":["1"],"availableVersion":"2"},{"name":"raycast","kind":"cask","installedVersions":["1"],"availableVersion":"2"},{"name":"PDF Expert","kind":"mas","installedVersions":["1"],"availableVersion":"2","storeId":1055273043}]}
JSON

jq -e '
  .schemaVersion == 1 and
  .success and
  .requiresApply and
  (.results | length == 4) and
  all(.results[]; .success)
' "$TEMP_DIR/result.json" >/dev/null

if "$REPO_DIR/bin/nix-me" action update >"$TEMP_DIR/invalid.json" <<'JSON'
{"items":[{"name":"unsafe; command","kind":"formula","installedVersions":[],"availableVersion":"2"}]}
JSON
then
  echo "Invalid update request was accepted" >&2
  exit 1
fi

jq -e '.error.code == "invalid_request"' "$TEMP_DIR/invalid.json" >/dev/null

NIX_ME_HOSTNAME=test-host NIX_ME_USERNAME=test-user \
  "$REPO_DIR/bin/nix-me" action apply >"$TEMP_DIR/apply.json"
jq -e '
  .schemaVersion == 1 and
  .action == "apply" and
  .success and
  (.message | contains("Would apply configuration for test-host as test-user"))
' "$TEMP_DIR/apply.json" >/dev/null

NIX_ME_HOSTNAME=test-host \
  "$REPO_DIR/bin/nix-me" action sync-projects >"$TEMP_DIR/projects.json"
jq -e '
  .schemaVersion == 1 and
  .action == "sync-projects" and
  .success and
  (.message | contains("Would sync projects for test-host"))
' "$TEMP_DIR/projects.json" >/dev/null

echo "nix-me action contract passed"
