#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: local-ai-setup [--download-model] [--force]

Build DS4 and connect it to the Pi coding agent. Model downloads are opt-in.

Options:
  --download-model  Download DeepSeek V4 Flash Q2 after setup (about 81 GiB)
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

if [[ "$(uname -s)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
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
  echo "==> Downloading DeepSeek V4 Flash Q2 (about 81 GiB)"
  bash "$ds4_dir/download_model.sh" ds4f-q2
else
  cat <<'EOF'

DS4 and Pi are connected. The model was not downloaded automatically.

Next steps:
  1. Run: local-ai-setup --download-model
  2. Start Pi: pi
  3. Run /model and select ds4/dsv4-flash-q2

You can also run /ds4 inside Pi to inspect or manage the runtime.
EOF
fi
