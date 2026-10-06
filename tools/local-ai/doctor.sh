#!/usr/bin/env bash
set -u

ds4_dir="${DS4_RUNTIME_DIR:-$HOME/src/ai/ds4}"
pi_ds4_dir="${PI_DS4_DIR:-$HOME/src/ai/pi-ds4}"
pi_agent_dir="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
model_name="${LOCAL_AI_MODEL_NAME:-DeepSeek V4 Flash Q2}"
model_path="${LOCAL_AI_MODEL_PATH:-$ds4_dir/ds4flash.gguf}"
recommended_memory_gib="${LOCAL_AI_RECOMMENDED_MEMORY_GIB:-96}"
required_free_disk_gib="${LOCAL_AI_REQUIRED_FREE_DISK_GIB:-100}"
pi_model="${LOCAL_AI_PI_MODEL:-ds4/dsv4-flash-q2}"
failures=0
warnings=0

status_usage() {
  cat <<'EOF'
Usage: local-ai-doctor [--json]

Inspect local DS4 and Pi state without changing it. JSON mode is intended for
the versioned management API and never builds, downloads, starts, or applies.
EOF
}

status_json=false
while (($# > 0)); do
  case "$1" in
    --json)
      status_json=true
      ;;
    -h | --help)
      status_usage
      exit 0
      ;;
    *)
      echo "error: unknown option: $1" >&2
      status_usage >&2
      exit 2
      ;;
  esac
  shift
done

emit_json_status() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "error: jq is required for local-ai-doctor --json" >&2
    return 69
  fi

  local extension_path support_path runtime_path pi_settings_file ds4_settings_file
  local ds4_state pi_ds4_state extension_state runtime_state model_state server_state
  local configuration_state configuration_drift_count probe_fixture probe_malformed
  local expected_provider expected_model remediation health summary has_unavailable has_degradation

  extension_path="${LOCAL_AI_EXTENSION_PATH:-$pi_agent_dir/extensions/pi-ds4}"
  support_path="${LOCAL_AI_SUPPORT_PATH:-$HOME/.pi/ds4/support}"
  runtime_path="$ds4_dir/ds4-server"
  pi_settings_file="${LOCAL_AI_PI_SETTINGS_FILE:-$pi_agent_dir/settings.json}"
  ds4_settings_file="${LOCAL_AI_DS4_SETTINGS_FILE:-$HOME/.pi/ds4/settings.json}"
  expected_provider="${pi_model%%/*}"
  expected_model="${pi_model#*/}"
  probe_fixture="${LOCAL_AI_STATUS_PROBE:-}"
  probe_malformed=false

  if [[ -n "$probe_fixture" ]]; then
    if [[ -r "$probe_fixture" ]] && jq -e '
      type == "object" and
      (.ds4Checkout | IN("ready", "missing", "invalid", "unavailable")) and
      (.piDs4Checkout | IN("ready", "missing", "invalid", "unavailable")) and
      (.extension | IN("linked", "missing", "mislinked", "unavailable")) and
      (.runtime | IN("built", "notBuilt", "unavailable")) and
      (.model | IN("present", "missing", "unavailable")) and
      (.server | IN("running", "stopped", "unavailable")) and
      (.configuration | type == "object") and
      (.configuration.state | IN("current", "drifted", "unavailable")) and
      (
        (.configuration.state == "current" and .configuration.driftCount == 0) or
        (.configuration.state == "drifted" and
          (.configuration.driftCount | type == "number" and . > 0 and floor == .)) or
        (.configuration.state == "unavailable" and .configuration.driftCount == null)
      )
    ' "$probe_fixture" >/dev/null 2>&1; then
      ds4_state="$(jq -r '.ds4Checkout' "$probe_fixture")"
      pi_ds4_state="$(jq -r '.piDs4Checkout' "$probe_fixture")"
      extension_state="$(jq -r '.extension' "$probe_fixture")"
      runtime_state="$(jq -r '.runtime' "$probe_fixture")"
      model_state="$(jq -r '.model' "$probe_fixture")"
      server_state="$(jq -r '.server' "$probe_fixture")"
      configuration_state="$(jq -r '.configuration.state' "$probe_fixture")"
      configuration_drift_count="$(jq -c '.configuration.driftCount' "$probe_fixture")"
    else
      probe_malformed=true
      ds4_state="unavailable"
      pi_ds4_state="unavailable"
      extension_state="unavailable"
      runtime_state="unavailable"
      model_state="unavailable"
      server_state="unavailable"
      configuration_state="unavailable"
      configuration_drift_count="null"
    fi
  else
    if [[ -d "$ds4_dir" && -r "$ds4_dir/Makefile" && -r "$ds4_dir/download_model.sh" ]]; then
      ds4_state="ready"
    elif [[ -e "$ds4_dir" ]]; then
      ds4_state="invalid"
    else
      ds4_state="missing"
    fi

    if [[ -d "$pi_ds4_dir" && -r "$pi_ds4_dir/install-pi-extension-local.sh" ]]; then
      pi_ds4_state="ready"
    elif [[ -e "$pi_ds4_dir" ]]; then
      pi_ds4_state="invalid"
    else
      pi_ds4_state="missing"
    fi

    if [[ -L "$extension_path" && -e "$extension_path" && -L "$support_path" && -e "$support_path" ]]; then
      if [[ "$(cd "$extension_path" 2>/dev/null && pwd -P)" == "$(cd "$pi_ds4_dir" 2>/dev/null && pwd -P)" ]] &&
        [[ "$(cd "$support_path" 2>/dev/null && pwd -P)" == "$(cd "$ds4_dir" 2>/dev/null && pwd -P)" ]]; then
        extension_state="linked"
      else
        extension_state="mislinked"
      fi
    elif [[ ! -e "$extension_path" && ! -L "$extension_path" && ! -e "$support_path" && ! -L "$support_path" ]]; then
      extension_state="missing"
    else
      extension_state="mislinked"
    fi

    if [[ "$ds4_state" == "unavailable" ]]; then
      runtime_state="unavailable"
    elif [[ -x "$runtime_path" ]]; then
      runtime_state="built"
    else
      runtime_state="notBuilt"
    fi

    if [[ "$ds4_state" == "unavailable" ]]; then
      model_state="unavailable"
    elif [[ -r "$model_path" ]]; then
      model_state="present"
    else
      model_state="missing"
      for candidate in "$ds4_dir"/gguf/*ds4*; do
        if [[ -r "$candidate" ]]; then
          model_state="present"
          break
        fi
      done
    fi

    case "${LOCAL_AI_SERVER_STATE_OVERRIDE:-}" in
      running | stopped | unavailable)
        server_state="$LOCAL_AI_SERVER_STATE_OVERRIDE"
        ;;
      "")
        if command -v pgrep >/dev/null 2>&1; then
          if pgrep -x ds4-server >/dev/null 2>&1; then
            server_state="running"
          elif [[ "$?" == "1" ]]; then
            server_state="stopped"
          else
            server_state="unavailable"
          fi
        else
          server_state="unavailable"
        fi
        ;;
      *)
        server_state="unavailable"
        ;;
    esac

    configuration_drift_count=0
    if [[ ! -r "$pi_settings_file" ]] || ! jq -e \
      --arg provider "$expected_provider" \
      --arg model "$expected_model" \
      '.defaultProvider == $provider and .defaultModel == $model' \
      "$pi_settings_file" >/dev/null 2>&1; then
      configuration_drift_count=$((configuration_drift_count + 1))
    fi
    if [[ ! -r "$ds4_settings_file" ]] || ! jq -e \
      --arg runtime "$ds4_dir" \
      '
        ."$schema" == "https://raw.githubusercontent.com/mitsuhiko/pi-ds4/main/settings.schema.json" and
        .protocol == "openai-responses" and
        .runtimeDir == $runtime and
        .autoUpdate == false and
        .contextTokens == 32768 and
        .power == 70 and
        .readyTimeoutMs == 900000
      ' \
      "$ds4_settings_file" >/dev/null 2>&1; then
      configuration_drift_count=$((configuration_drift_count + 1))
    fi
    if ((configuration_drift_count == 0)); then
      configuration_state="current"
    else
      configuration_state="drifted"
    fi
  fi

  remediation='[]'
  add_remediation() {
    remediation="$(jq -c --arg message "$1" '. + [$message]' <<<"$remediation")"
  }

  case "$ds4_state" in
    missing | invalid) add_remediation "Run make sync-projects to restore the DS4 checkout." ;;
  esac
  case "$pi_ds4_state" in
    missing | invalid) add_remediation "Run make sync-projects to restore the pi-ds4 checkout." ;;
  esac
  case "$runtime_state" in
    notBuilt) add_remediation "Run local-ai-setup to build the DS4 runtime." ;;
  esac
  case "$extension_state" in
    missing | mislinked) add_remediation "Run local-ai-setup to relink the pi-ds4 extension and runtime support." ;;
  esac
  case "$model_state" in
    missing) add_remediation "Run local-ai-setup --download-model to install $model_name." ;;
  esac
  if [[ "$configuration_state" == "drifted" ]]; then
    add_remediation "Run make switch to restore the local-AI harness configuration."
  fi

  has_unavailable=false
  for state in \
    "$ds4_state" "$pi_ds4_state" "$extension_state" "$runtime_state" \
    "$model_state" "$server_state" "$configuration_state"; do
    if [[ "$state" == "unavailable" ]]; then
      has_unavailable=true
    fi
  done

  has_degradation=false
  if [[ "$ds4_state" != "ready" || "$pi_ds4_state" != "ready" ||
    "$extension_state" != "linked" || "$runtime_state" != "built" ||
    "$model_state" != "present" || "$configuration_state" != "current" ]]; then
    has_degradation=true
  fi

  if [[ "$has_unavailable" == true ]]; then
    health="unavailable"
    summary="Local AI status is unavailable"
    if [[ "$probe_malformed" == true ]]; then
      add_remediation "Remove or repair the malformed local-AI status probe, then refresh."
    else
      add_remediation "Run local-ai-doctor --json to retry the unavailable checks."
    fi
  elif [[ "$has_degradation" == true ]]; then
    health="degraded"
    summary="Local AI needs attention"
  else
    health="healthy"
    if [[ "$server_state" == "running" ]]; then
      summary="Local AI is ready and serving"
    else
      summary="Local AI is ready; the server is stopped"
    fi
  fi

  jq -n \
    --arg health "$health" \
    --arg summary "$summary" \
    --arg ds4State "$ds4_state" \
    --arg ds4Path "$ds4_dir" \
    --arg piDs4State "$pi_ds4_state" \
    --arg piDs4Path "$pi_ds4_dir" \
    --arg extensionState "$extension_state" \
    --arg extensionPath "$extension_path" \
    --arg runtimeState "$runtime_state" \
    --arg runtimePath "$runtime_path" \
    --arg modelState "$model_state" \
    --arg modelName "$model_name" \
    --arg modelPath "$model_path" \
    --arg serverState "$server_state" \
    --arg configurationState "$configuration_state" \
    --argjson configurationDriftCount "$configuration_drift_count" \
    --argjson remediation "$remediation" \
    '{
      schemaVersion: 1,
      health: $health,
      summary: $summary,
      ds4Checkout: {state: $ds4State, path: $ds4Path},
      piDs4Checkout: {state: $piDs4State, path: $piDs4Path},
      extension: {state: $extensionState, path: $extensionPath},
      runtime: {state: $runtimeState, path: $runtimePath},
      model: {state: $modelState, name: $modelName, path: $modelPath},
      server: {state: $serverState},
      configuration: {state: $configurationState, driftCount: $configurationDriftCount},
      remediation: $remediation
    }'
}

if [[ "$status_json" == true ]]; then
  emit_json_status
  exit $?
fi

pass() {
  printf 'PASS  %s\n' "$1"
}

warn() {
  printf 'WARN  %s\n' "$1"
  warnings=$((warnings + 1))
}

fail() {
  printf 'FAIL  %s\n' "$1"
  failures=$((failures + 1))
}

arm64_supported="$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null || printf '0')"
if [[ "$(uname -s)" == "Darwin" && "$arm64_supported" == "1" ]]; then
  pass "Apple Silicon Mac detected"
else
  fail "DS4 requires an Apple Silicon Mac"
fi

if xcode-select -p >/dev/null 2>&1; then
  pass "Xcode Command Line Tools are installed"
else
  fail "Xcode Command Line Tools are missing; run: xcode-select --install"
fi

if command -v pi >/dev/null 2>&1; then
  pass "Pi is available at $(command -v pi)"
else
  fail "Pi is not installed; apply the local-ai profile"
fi

if [[ -f "$ds4_dir/Makefile" ]]; then
  pass "DS4 checkout exists at $ds4_dir"
else
  fail "DS4 checkout is missing at $ds4_dir"
fi

if [[ -f "$pi_ds4_dir/install-pi-extension-local.sh" ]]; then
  pass "pi-ds4 checkout exists at $pi_ds4_dir"
else
  fail "pi-ds4 checkout is missing at $pi_ds4_dir"
fi

if [[ -x "$ds4_dir/ds4-server" ]]; then
  pass "DS4 server is built"
else
  warn "DS4 server is not built; run: local-ai-setup"
fi

if [[ -L "$pi_agent_dir/extensions/pi-ds4" && -e "$pi_agent_dir/extensions/pi-ds4" ]]; then
  pass "Pi DS4 extension is linked"
else
  warn "Pi DS4 extension is not linked; run: local-ai-setup"
fi

support_link="$HOME/.pi/ds4/support"
if [[ -L "$support_link" && -e "$support_link" ]] &&
  [[ "$(cd "$support_link" && pwd -P)" == "$(cd "$ds4_dir" 2>/dev/null && pwd -P)" ]]; then
  pass "Pi DS4 runtime points to $ds4_dir"
else
  warn "Pi DS4 runtime does not point to $ds4_dir; run: local-ai-setup"
fi

settings_file="$HOME/.pi/ds4/settings.json"
if [[ -f "$settings_file" ]] && jq -e --arg runtime "$ds4_dir" '
  .protocol == "openai-responses" and .runtimeDir == $runtime
' "$settings_file" >/dev/null 2>&1; then
  pass "Pi DS4 settings are valid"
else
  warn "Pi DS4 settings are missing or do not match the configured runtime"
fi

shopt -s nullglob
model_files=("$ds4_dir"/gguf/*ds4*)
model_present=false
if [[ -e "$model_path" ]] || ((${#model_files[@]} > 0)); then
  model_present=true
  pass "$model_name is present"
else
  warn "$model_name is not present; run: local-ai-setup --download-model"
fi

if [[ "$(uname -s)" == "Darwin" ]]; then
  ram_bytes="$(/usr/sbin/sysctl -n hw.memsize 2>/dev/null || printf '0')"
  ram_gib=$((ram_bytes / 1073741824))
  if ((ram_gib >= recommended_memory_gib)); then
    pass "Memory is ${ram_gib} GiB (${recommended_memory_gib} GiB or more recommended)"
  else
    warn "Memory is ${ram_gib} GiB; $model_name recommends about ${recommended_memory_gib} GiB"
  fi
fi

if [[ "$model_present" == true ]]; then
  pass "Initial model download disk check is no longer required"
else
  free_kib="$(df -Pk "$HOME" 2>/dev/null | awk 'NR == 2 { print $4 }')"
  if [[ ! "$free_kib" =~ ^[0-9]+$ ]]; then
    free_kib=0
  fi
  free_gib=$((free_kib / 1048576))
  if ((free_gib >= required_free_disk_gib)); then
    pass "Home volume has ${free_gib} GiB free (${required_free_disk_gib} GiB required before download)"
  else
    warn "Home volume has ${free_gib} GiB free; reserve at least ${required_free_disk_gib} GiB before downloading $model_name"
  fi
fi

printf '\n%d failure(s), %d warning(s)\n' "$failures" "$warnings"
if ((failures > 0)); then
  exit 1
fi
