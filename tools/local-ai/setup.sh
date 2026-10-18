#!/usr/bin/env bash
set -euo pipefail

model_name="${LOCAL_AI_MODEL_NAME:-DeepSeek V4 Flash Q2}"
download_size_gib="${LOCAL_AI_DOWNLOAD_SIZE_GIB:-81}"

usage() {
  cat <<EOF
Usage: local-ai-setup [--download-model]

Build DS4 eagerly and verify its Pi package configuration. Pi can also build
DS4 lazily on first use. Model downloads are always opt-in.

Options:
  --download-model  Start an explicit ${model_name} download (about ${download_size_gib} GiB)
  -h, --help        Show this help
EOF
}

download_model=false

while (($# > 0)); do
  case "$1" in
    --download-model)
      download_model=true
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

if [[ ! -f "$ds4_dir/Makefile" || ! -f "$ds4_dir/download_model.sh" || ! -f "$ds4_dir/ds4_server.c" ]]; then
  echo "error: DS4 checkout not found at $ds4_dir" >&2
  echo "       run 'make sync-projects' from the nix-me checkout first" >&2
  exit 1
fi

if [[ ! -f "$pi_ds4_dir/package.json" || ! -f "$pi_ds4_dir/index.ts" ]]; then
  echo "error: pi-ds4 checkout not found at $pi_ds4_dir" >&2
  echo "       run 'make sync-projects' from the nix-me checkout first" >&2
  exit 1
fi

pi_settings="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/settings.json"
if [[ ! -r "$pi_settings" ]] || ! command -v jq >/dev/null 2>&1 ||
  ! jq -e --arg package "$pi_ds4_dir" '
    .packages | arrays | any(.[];
      . == $package or . == "~/src/ai/pi-ds4" or
      ((type == "object") and (.source == $package or .source == "~/src/ai/pi-ds4")))
  ' "$pi_settings" >/dev/null 2>&1; then
  echo "error: Pi is not configured to load the pi-ds4 package" >&2
  echo "       apply the local-ai profile with 'make switch' first" >&2
  exit 1
fi

echo "==> Building DS4 in $ds4_dir"
make -C "$ds4_dir" ds4-server

echo "==> Pi package configured: $pi_ds4_dir"

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
  printf '\nPi and DS4 are configured. %s was not downloaded automatically.\n\n' "$model_name"
  printf 'Next steps:\n'
  printf '  1. Run: local-ai-model start\n'
  printf '  2. Start Pi: pi\n'
  printf '  3. Run /model and select %s\n\n' "$pi_model"
  printf 'You can also run /ds4 inside Pi to download or inspect the runtime.\n'
fi
