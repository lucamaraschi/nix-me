#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "$script_dir/../.." && pwd)"
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p \
  "$tmp_dir/apps/cli/lib" \
  "$tmp_dir/nix/hosts/profiles" \
  "$tmp_dir/nix/hosts/machines"
cp "$repo_dir/flake.nix" "$tmp_dir/flake.nix"
cp "$repo_dir/apps/cli/lib/config-builder.sh" "$tmp_dir/apps/cli/lib/config-builder.sh"
cp "$repo_dir/apps/cli/lib/ui.sh" "$tmp_dir/apps/cli/lib/ui.sh"
cp "$repo_dir/nix/hosts/profiles/dev.nix" "$tmp_dir/nix/hosts/profiles/dev.nix"
cp "$repo_dir/nix/hosts/profiles/work.nix" "$tmp_dir/nix/hosts/profiles/work.nix"

NIX_ME_CONFIG_DIR="$tmp_dir" "$repo_dir/tools/installation/create-machine.sh" \
  test-mac macbook-pro "Test Mac" tester true dev work >/dev/null

host_config="$tmp_dir/nix/hosts/machines/test-mac/default.nix"
test -f "$host_config"
grep -q 'apps.state.enable = true;' "$host_config"
grep -q 'apps.manager.enable = true;' "$host_config"
grep -q '"test-mac" = mkDarwinSystem' "$tmp_dir/flake.nix"
grep -q './nix/hosts/profiles/dev.nix' "$tmp_dir/flake.nix"
grep -q './nix/hosts/profiles/work.nix' "$tmp_dir/flake.nix"

before=$(cksum "$host_config" "$tmp_dir/flake.nix")
NIX_ME_CONFIG_DIR="$tmp_dir" "$repo_dir/tools/installation/create-machine.sh" \
  test-mac macmini "Changed Name" tester false >/dev/null
after=$(cksum "$host_config" "$tmp_dir/flake.nix")
test "$before" = "$after"

if NIX_ME_CONFIG_DIR="$tmp_dir" "$repo_dir/tools/installation/create-machine.sh" \
  'Bad Host' macbook "Bad Host" tester false >/dev/null 2>&1; then
  echo "expected an invalid hostname to fail" >&2
  exit 1
fi

if NIX_ME_CONFIG_DIR="$tmp_dir" "$repo_dir/tools/installation/create-machine.sh" \
  another-mac macbook "Another Mac" tester false missing-profile >/dev/null 2>&1; then
  echo "expected an unknown profile to fail" >&2
  exit 1
fi

if NIX_ME_CONFIG_DIR="$tmp_dir" "$repo_dir/tools/installation/create-machine.sh" \
  another-mac macbook 'Unsafe ${builtins.abort "injected"}' tester false >/dev/null 2>&1; then
  echo "expected Nix string interpolation in a machine name to fail" >&2
  exit 1
fi

echo "machine configuration tests passed"
