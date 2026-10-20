#!/bin/bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: create-machine.sh HOSTNAME MACHINE_TYPE MACHINE_NAME USERNAME APP_STATE [PROFILE...]

Creates a new nix-me host configuration without interactive prompts. Existing
host definitions are left unchanged.
EOF
}

if [[ $# -lt 5 ]]; then
  usage >&2
  exit 64
fi

host_name="$1"
machine_type="$2"
machine_name="$3"
user_name="$4"
app_state="$5"
shift 5
profiles=("$@")

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="${NIX_ME_CONFIG_DIR:-$(cd "$script_dir/../.." && pwd)}"

if [[ ! "$host_name" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
  echo "Hostname must use lowercase letters, numbers, and hyphens." >&2
  exit 65
fi
case "$machine_type" in
  macbook|macbook-pro|macmini|vm) ;;
  *)
    echo "Unsupported machine type: $machine_type" >&2
    exit 65
    ;;
esac
if [[ ! "$user_name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
  echo "Username contains unsupported characters." >&2
  exit 65
fi
if [[ -z "$machine_name" || "$machine_name" == *$'\n'* || "$machine_name" == *'"'* ||
  "$machine_name" == *'\\'* || "$machine_name" == *'${'* ]]; then
  echo "Machine name contains unsupported characters." >&2
  exit 65
fi
case "$app_state" in
  true|false) ;;
  *)
    echo "APP_STATE must be true or false." >&2
    exit 65
    ;;
esac
if [[ ! -f "$repo_dir/flake.nix" ]]; then
  echo "No nix-me flake found at $repo_dir" >&2
  exit 66
fi

for profile in ${profiles[@]+"${profiles[@]}"}; do
  if [[ ! "$profile" =~ ^[a-z0-9][a-z0-9-]*$ ]] ||
    [[ ! -f "$repo_dir/nix/hosts/profiles/$profile.nix" ]]; then
    echo "Unknown profile: $profile" >&2
    exit 65
  fi
done

host_dir="$repo_dir/nix/hosts/machines/$host_name"
if grep -Fq "\"$host_name\" =" "$repo_dir/flake.nix"; then
  if [[ -f "$host_dir/default.nix" ]]; then
    echo "Machine $host_name already exists; leaving it unchanged."
    exit 0
  fi
  echo "flake.nix defines $host_name but $host_dir/default.nix is missing." >&2
  exit 78
fi
if [[ -e "$host_dir" ]]; then
  echo "$host_dir already exists without a matching flake entry." >&2
  exit 78
fi

export NON_INTERACTIVE=1
export WIZARD_APP_STATE_ENABLE="$app_state"
export WIZARD_MANAGER_ENABLE=true

# shellcheck source=../../apps/cli/lib/config-builder.sh
source "$repo_dir/apps/cli/lib/config-builder.sh"
generate_machine_config_multi_profile \
  "$host_name" \
  "$machine_type" \
  "$machine_name" \
  "$user_name" \
  "$repo_dir" \
  ${profiles[@]+"${profiles[@]}"}

echo "Created machine configuration for $host_name."
