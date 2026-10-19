#!/bin/bash
set -euo pipefail

: "${FAKE_SHA256_MARKER:?FAKE_SHA256_MARKER is required}"

printf 'verifying\n' >"$FAKE_SHA256_MARKER"
trap 'exit 143' TERM INT
while true; do
  sleep 1
done
