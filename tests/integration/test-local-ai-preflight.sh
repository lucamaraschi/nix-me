#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
preflight="$repo_dir/tools/local-ai/preflight.sh"
fixture_dir="$(mktemp -d)"
missing_model="$fixture_dir/missing-model.gguf"

bash "$repo_dir/tests/integration/local-ai/test-status.sh"

if [[ "$(uname -s)" != "Darwin" ]] ||
  [[ "$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null || printf '0')" != "1" ]]; then
  if output="$(LOCAL_AI_MODEL_PATH="$missing_model" bash "$preflight" 2>&1)"; then
    echo "local AI preflight unexpectedly accepted unsupported hardware" >&2
    exit 1
  fi
  grep -q "requires an Apple Silicon Mac" <<<"$output"
  echo "local AI unsupported-hardware preflight passed"
  exit 0
fi

output="$(
  LOCAL_AI_MODEL_PATH="$missing_model" \
    LOCAL_AI_REQUIREMENTS_ENFORCEMENT=warn \
    bash "$preflight" 2>&1
)"
grep -q "Local AI preflight completed" <<<"$output"

if output="$(
  LOCAL_AI_MODEL_PATH="$missing_model" \
    LOCAL_AI_RECOMMENDED_MEMORY_GIB=999999 \
    LOCAL_AI_REQUIRED_FREE_DISK_GIB=0 \
    LOCAL_AI_REQUIREMENTS_ENFORCEMENT=fail \
    bash "$preflight" 2>&1
)"; then
  echo "strict local AI memory preflight unexpectedly passed" >&2
  exit 1
fi
grep -q "recommends 999999 GiB of memory" <<<"$output"

if output="$(
  LOCAL_AI_MODEL_PATH="$missing_model" \
    LOCAL_AI_RECOMMENDED_MEMORY_GIB=0 \
    LOCAL_AI_REQUIRED_FREE_DISK_GIB=999999 \
    LOCAL_AI_REQUIREMENTS_ENFORCEMENT=fail \
    bash "$preflight" 2>&1
)"; then
  echo "strict local AI disk preflight unexpectedly passed" >&2
  exit 1
fi
grep -q "needs about 999999 GiB free" <<<"$output"

present_model="$fixture_dir/present-model.gguf"
touch "$present_model"
LOCAL_AI_MODEL_PATH="$present_model" \
  LOCAL_AI_RECOMMENDED_MEMORY_GIB=0 \
  LOCAL_AI_REQUIRED_FREE_DISK_GIB=999999 \
  LOCAL_AI_REQUIREMENTS_ENFORCEMENT=fail \
  bash "$preflight" >/dev/null 2>&1

echo "local AI preflight policy passed"
