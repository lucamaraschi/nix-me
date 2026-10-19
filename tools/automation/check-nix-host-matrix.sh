#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
flake="${NIX_ME_FLAKE:-$repo_root}"
manifest="${NIX_ME_HOST_MATRIX:-$repo_root/nix/host-matrix.json}"

for command in jq nix; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "$command is required" >&2
    exit 69
  fi
done

if ! jq -e '
  def string_array:
    type == "array"
    and all(.[]; type == "string" and length > 0)
    and length == (unique | length);
  (keys | sort) == [
    "darwinConfigurations",
    "homeConfigurations",
    "nixosConfigurations"
  ]
  and (.darwinConfigurations | string_array)
  and (.nixosConfigurations | string_array)
  and (.homeConfigurations | string_array)
' "$manifest" >/dev/null; then
  echo "Invalid host matrix: $manifest" >&2
  exit 65
fi

check_output_inventory() {
  local output="$1"
  local expected actual

  expected="$(jq -c --arg output "$output" '.[$output] | sort' "$manifest")"
  actual="$(nix eval --json --apply builtins.attrNames "$flake#$output" | jq -c 'sort')"

  if [[ "$actual" != "$expected" ]]; then
    echo "The $output inventory does not match $manifest" >&2
    echo "Expected: $expected" >&2
    echo "Actual:   $actual" >&2
    echo "Update the flake and host matrix together so every configuration is evaluated." >&2
    exit 65
  fi
}

evaluate_output() {
  local output="$1"
  local attribute_suffix="$2"
  local name drv_path

  while IFS= read -r name; do
    printf 'Evaluating %s.%s... ' "$output" "$name"
    drv_path="$(
      USERNAME="${NIX_ME_EVALUATION_USER:-batman}" \
        nix eval --impure --raw \
        "$flake#$output.\"$name\".$attribute_suffix"
    )"
    printf '%s\n' "$drv_path"
  done < <(jq -r --arg output "$output" '.[$output][]' "$manifest")
}

check_output_inventory darwinConfigurations
check_output_inventory nixosConfigurations
check_output_inventory homeConfigurations

evaluate_output darwinConfigurations system.drvPath
evaluate_output nixosConfigurations config.system.build.toplevel.drvPath
evaluate_output homeConfigurations activationPackage.drvPath

echo "Every declared host configuration evaluated successfully"
