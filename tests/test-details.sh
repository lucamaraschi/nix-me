#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nix-me-details-test.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

cat >"$TEMP_DIR/manifest.json" <<'JSON'
{"software":{"nixPackageDetails":[{"name":"ripgrep","fullName":"ripgrep-14.1.1","version":"14.1.1","description":"A fast search tool","homepage":"https://github.com/BurntSushi/ripgrep","license":"Unlicense"}]}}
JSON

NIX_ME_DETAILS_MANIFEST="$TEMP_DIR/manifest.json" \
  "$REPO_DIR/bin/nix-me" details nix ripgrep >"$TEMP_DIR/details.json"

jq -e '
  .schemaVersion == 1 and
  .kind == "nix" and
  .name == "ripgrep" and
  .version == "14.1.1" and
  (.description | type == "string")
' "$TEMP_DIR/details.json" >/dev/null

if "$REPO_DIR/bin/nix-me" details invalid package >"$TEMP_DIR/invalid.json"; then
  echo "Invalid detail kind unexpectedly succeeded" >&2
  exit 1
fi
jq -e '.error.code == "invalid_kind"' "$TEMP_DIR/invalid.json" >/dev/null

echo "nix-me package details contract passed"
