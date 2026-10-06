#!/usr/bin/env bash
set -euo pipefail

model_name="${LOCAL_AI_MODEL_NAME:-the configured local model}"
model_path="${LOCAL_AI_MODEL_PATH:-${HOME}/src/ai/ds4/ds4flash.gguf}"
local_ai_home="${LOCAL_AI_HOME:-${HOME}}"
recommended_memory_gib="${LOCAL_AI_RECOMMENDED_MEMORY_GIB:-96}"
required_free_disk_gib="${LOCAL_AI_REQUIRED_FREE_DISK_GIB:-100}"
enforcement="${LOCAL_AI_REQUIREMENTS_ENFORCEMENT:-warn}"
warnings=0
capacity_failures=0

require_integer() {
  local name="$1"
  local value="$2"

  if [[ ! "$value" =~ ^[0-9]+$ ]]; then
    echo "ERROR local AI requirement ${name} must be a non-negative integer, got: ${value}" >&2
    exit 2
  fi
}

capacity_issue() {
  local message="$1"

  if [[ "$enforcement" == "fail" ]]; then
    echo "ERROR ${message}" >&2
    capacity_failures=$((capacity_failures + 1))
  else
    echo "WARN  ${message}" >&2
    warnings=$((warnings + 1))
  fi
}

case "$enforcement" in
  warn | fail) ;;
  *)
    echo "ERROR local AI enforcement must be 'warn' or 'fail', got: ${enforcement}" >&2
    exit 2
    ;;
esac

require_integer "recommendedMemoryGiB" "$recommended_memory_gib"
require_integer "requiredFreeDiskGiB" "$required_free_disk_gib"

os_name="$(uname -s)"
arm64_supported="$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null || printf '0')"
if [[ "$os_name" != "Darwin" || "$arm64_supported" != "1" ]]; then
  echo "ERROR ${model_name} requires an Apple Silicon Mac" >&2
  exit 1
fi
echo "PASS  Apple Silicon Mac detected" >&2

ram_bytes="$(/usr/sbin/sysctl -n hw.memsize 2>/dev/null || printf '0')"
if [[ "$ram_bytes" =~ ^[0-9]+$ ]] && ((ram_bytes > 0)); then
  ram_gib=$((ram_bytes / 1073741824))
  if ((ram_gib < recommended_memory_gib)); then
    capacity_issue "${model_name} recommends ${recommended_memory_gib} GiB of memory; this machine has ${ram_gib} GiB"
  else
    echo "PASS  Memory is ${ram_gib} GiB (${recommended_memory_gib} GiB recommended)" >&2
  fi
else
  capacity_issue "Unable to determine system memory for ${model_name}"
fi

if [[ -e "$model_path" ]]; then
  echo "PASS  Model is already present at ${model_path}" >&2
else
  free_kib="$(df -Pk "$local_ai_home" 2>/dev/null | awk 'NR == 2 { print $4 }')"
  if [[ "$free_kib" =~ ^[0-9]+$ ]]; then
    free_gib=$((free_kib / 1048576))
    if ((free_gib < required_free_disk_gib)); then
      capacity_issue "${model_name} needs about ${required_free_disk_gib} GiB free before its first download; ${free_gib} GiB is available"
    else
      echo "PASS  Free disk is ${free_gib} GiB (${required_free_disk_gib} GiB required before download)" >&2
    fi
  else
    capacity_issue "Unable to determine free disk space for ${model_name}"
  fi
fi

if ((capacity_failures > 0)); then
  echo "ERROR Local AI preflight failed with ${capacity_failures} capacity issue(s)" >&2
  exit 1
fi

if ((warnings > 0)); then
  echo "WARN  Local AI preflight completed with ${warnings} warning(s)" >&2
else
  echo "PASS  Local AI preflight completed" >&2
fi
