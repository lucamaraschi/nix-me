#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nix-me-api-test.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

export NIX_ME_CONFIG_DIR="$REPO_DIR"
export NIX_ME_SKIP_UPDATES=1

"$REPO_DIR/bin/nix-me" api snapshot >"$TEMP_DIR/snapshot.json"

jq -e '
  .schemaVersion == 1 and
  (.generatedAt | type == "string") and
  (.host.hostname | type == "string") and
  (.configuration.applyState | IN("current", "pending", "unknown")) and
  ((.configuration.desiredSource | type) == "object") and
  (.inventory.desired.nixPackages | type == "array") and
  (.inventory.desired.nixPackageDetails | type == "array") and
  (.inventory.desired.homebrew.casks | type == "array") and
  (.updates.homebrew | type == "array") and
  (.updates.macAppStore | type == "array") and
  (.updates.nixFlake | type == "array") and
  (.projects | type == "array") and
  (.warnings | type == "array")
' "$TEMP_DIR/snapshot.json" >/dev/null

for endpoint in status inventory updates projects manifest; do
  "$REPO_DIR/bin/nix-me" api "$endpoint" >"$TEMP_DIR/$endpoint.json"
  jq -e '.schemaVersion == 1' "$TEMP_DIR/$endpoint.json" >/dev/null
done

echo "nix-me API contract passed"
