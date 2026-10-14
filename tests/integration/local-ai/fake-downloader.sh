#!/bin/bash
set -euo pipefail

: "${DS4_GGUF_DIR:?DS4_GGUF_DIR is required}"
mode="${FAKE_DOWNLOAD_MODE:-success}"
content="${FAKE_MODEL_CONTENT:-model-data}"
part="$DS4_GGUF_DIR/model.gguf.part"
model="$DS4_GGUF_DIR/model.gguf"

if [[ -n "${FAKE_DOWNLOAD_LOG:-}" ]]; then
  printf '%s\n' "$mode" >>"$FAKE_DOWNLOAD_LOG"
fi

case "$mode" in
  success)
    printf '%s' "$content" >"$part"
    mv "$part" "$model"
    # Upstream DS4 links relative to the downloader script ROOT, not GGUF_DIR.
    ln -s "$model" "$(dirname "$0")/ds4flash.gguf"
    printf 'runner-relative symlink regression fixture\n' >"$DS4_GGUF_DIR/download.metadata"
    ;;
  fail)
    printf 'partial-data' >"$part"
    echo "fake downloader failure" >&2
    exit 42
    ;;
  slow)
    trap 'exit 143' TERM INT
    while true; do
      printf 'partial-data' >>"$part"
      sleep 0.05
    done
    ;;
  *)
    echo "unknown fake mode: $mode" >&2
    exit 64
    ;;
esac
