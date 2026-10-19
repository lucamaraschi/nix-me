#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
RECIPE_DIR="$REPO_DIR/packages/app-state/recipes"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

for command in jq nix; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "configured app coverage requires $command" >&2
    exit 1
  fi
done

host_names="$(nix eval --option warn-dirty false --impure --json "$REPO_DIR#darwinConfigurations" --apply builtins.attrNames)"
: >"$TEMP_DIR/configured-casks"
: >"$TEMP_DIR/configured-mas"

while IFS= read -r host; do
  nix eval --option warn-dirty false --impure --json "$REPO_DIR#darwinConfigurations.$host.config.homebrew.casks" \
    | jq -r '.[].name' >>"$TEMP_DIR/configured-casks"
  nix eval --option warn-dirty false --impure --json "$REPO_DIR#darwinConfigurations.$host.config.homebrew.masApps" \
    | jq -r '.[]' >>"$TEMP_DIR/configured-mas"
done < <(jq -r '.[]' <<<"$host_names")

sort -u -o "$TEMP_DIR/configured-casks" "$TEMP_DIR/configured-casks"
sort -u -o "$TEMP_DIR/configured-mas" "$TEMP_DIR/configured-mas"

awk '
  /^install:[[:space:]]*$/ { in_install = 1; next }
  in_install && /^[^[:space:]#]/ { in_install = 0 }
  in_install && /^[[:space:]]+cask:[[:space:]]*/ {
    value = $0
    sub(/^[[:space:]]+cask:[[:space:]]*/, "", value)
    gsub(/["\047]/, "", value)
    print value
  }
' "$RECIPE_DIR"/*.yaml | sort -u >"$TEMP_DIR/recipe-casks"

awk '
  /^install:[[:space:]]*$/ { in_install = 1; next }
  in_install && /^[^[:space:]#]/ { in_install = 0 }
  in_install && /^[[:space:]]+mas:[[:space:]]*/ {
    value = $0
    sub(/^[[:space:]]+mas:[[:space:]]*/, "", value)
    gsub(/[[:space:]]/, "", value)
    print value
  }
' "$RECIPE_DIR"/*.yaml | sort -u >"$TEMP_DIR/recipe-mas"

comm -23 "$TEMP_DIR/configured-casks" "$TEMP_DIR/recipe-casks" >"$TEMP_DIR/missing-casks"
comm -23 "$TEMP_DIR/configured-mas" "$TEMP_DIR/recipe-mas" >"$TEMP_DIR/missing-mas"

if [[ -s "$TEMP_DIR/missing-casks" || -s "$TEMP_DIR/missing-mas" ]]; then
  if [[ -s "$TEMP_DIR/missing-casks" ]]; then
    echo "Configured Homebrew casks without an app-state integration:" >&2
    sed 's/^/  - /' "$TEMP_DIR/missing-casks" >&2
  fi
  if [[ -s "$TEMP_DIR/missing-mas" ]]; then
    echo "Configured Mac App Store apps without an app-state integration:" >&2
    sed 's/^/  - /' "$TEMP_DIR/missing-mas" >&2
  fi
  exit 1
fi

echo "Configured app recipe coverage passed"
