#!/usr/bin/env bash
set -euo pipefail

model_name="${LOCAL_AI_MODEL_NAME:-DeepSeek V4 Flash Q2}"
download_size_gib="${LOCAL_AI_DOWNLOAD_SIZE_GIB:-81}"

usage() {
  cat <<EOF
Usage: local-ai-setup [--download-model] [--force]

Build DS4 and connect it to the Pi coding agent. Model downloads are opt-in.

Options:
  --download-model  Start an explicit ${model_name} download (about ${download_size_gib} GiB)
  --force           Replace an existing Pi DS4 support directory, preserving a backup
  -h, --help        Show this help
EOF
}

download_model=false
force=false

while (($# > 0)); do
  case "$1" in
    --download-model)
      download_model=true
      ;;
    --force)
      force=true
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

ds4_dir="${DS4_RUNTIME_DIR:-$HOME/src/ai/ds4}"
pi_ds4_dir="${PI_DS4_DIR:-$HOME/src/ai/pi-ds4}"
pi_model="${LOCAL_AI_PI_MODEL:-ds4/dsv4-flash-q2}"

arm64_supported="$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null || printf '0')"
if [[ "$(uname -s)" != "Darwin" || "$arm64_supported" != "1" ]]; then
  echo "error: DS4 currently requires an Apple Silicon Mac" >&2
  exit 1
fi

if ! xcode-select -p >/dev/null 2>&1; then
  echo "error: Xcode Command Line Tools are required; run: xcode-select --install" >&2
  exit 1
fi

if ! command -v pi >/dev/null 2>&1; then
  echo "error: Pi is not installed; apply the local-ai profile first" >&2
  exit 1
fi

if [[ ! -f "$ds4_dir/Makefile" || ! -f "$ds4_dir/download_model.sh" ]]; then
  echo "error: DS4 checkout not found at $ds4_dir" >&2
  echo "       run 'make sync-projects' from the nix-me checkout first" >&2
  exit 1
fi

installer="$pi_ds4_dir/install-pi-extension-local.sh"
if [[ ! -f "$installer" ]]; then
  echo "error: pi-ds4 checkout not found at $pi_ds4_dir" >&2
  echo "       run 'make sync-projects' from the nix-me checkout first" >&2
  exit 1
fi

echo "==> Building DS4 in $ds4_dir"
make -C "$ds4_dir"

echo "==> Connecting Pi to the local DS4 checkout"
installer_args=("$ds4_dir")
if [[ "$force" == true ]]; then
  installer_args=(--force "$ds4_dir")
fi
bash "$installer" "${installer_args[@]}"

if [[ "$download_model" == true ]]; then
  echo "==> Starting explicit ${model_name} download (about ${download_size_gib} GiB)"
  if ! command -v local-ai-model >/dev/null 2>&1; then
    echo "error: local-ai-model is not installed; apply the local-ai profile first" >&2
    exit 1
  fi
  printf '{}\n' | local-ai-model start
  printf '\nTrack progress with: local-ai-model status\n'
  printf 'Cancel safely with:  local-ai-model cancel\n'
else
  printf '\nDS4 and Pi are connected. %s was not downloaded automatically.\n\n' "$model_name"
  printf 'Next steps:\n'
  printf '  1. Run: local-ai-model start\n'
  printf '  2. Start Pi: pi\n'
  printf '  3. Run /model and select %s\n\n' "$pi_model"
  printf 'You can also run /ds4 inside Pi to inspect or manage the runtime.\n'
fi
