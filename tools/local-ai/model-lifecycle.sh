#!/bin/bash

# Explicit, asynchronous model installation for the local-AI profile.
set -uo pipefail

umask 077

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
STATE_ROOT="${LOCAL_AI_OPERATION_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/nix-me/local-ai-model}"
STATE_FILE="$STATE_ROOT/state.json"
LOG_FILE="$STATE_ROOT/operation.log"
DS4_DIR="${DS4_RUNTIME_DIR:-$HOME/src/ai/ds4}"
MODEL_PATH="${LOCAL_AI_MODEL_PATH:-$DS4_DIR/ds4flash.gguf}"
MODEL_NAME="${LOCAL_AI_MODEL_NAME:-DeepSeek V4 Flash Q2}"
DOWNLOAD_TARGET="${LOCAL_AI_DOWNLOAD_TARGET:-ds4f-q2}"
DOWNLOAD_SIZE_GIB="${LOCAL_AI_DOWNLOAD_SIZE_GIB:-81}"
REQUIRED_FREE_GIB="${LOCAL_AI_REQUIRED_FREE_DISK_GIB:-100}"
DOWNLOAD_PROGRAM="${LOCAL_AI_DOWNLOAD_PROGRAM:-$DS4_DIR/download_model.sh}"
START_LOCK_HELD=false
START_LOCK_STARTED_AT=""
START_LOCK_ACTION=""

usage() {
  cat <<'EOF'
Usage: local-ai-model <start|status|cancel>

start reads an optional JSON object from stdin:
  {"expectedSha256":"<64 lowercase or uppercase hexadecimal characters>"}

The command never downloads a model during status. start is the only operation
that launches a downloader; cancel explicitly terminates the active operation.
EOF
}

fail_json() {
  local code="$1"
  local message="$2"
  jq -n --arg code "$code" --arg message "$message" \
    '{schemaVersion: 1, error: {code: $code, message: $message}}'
}

is_uint() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

valid_path() {
  [[ "$1" == /* && "$1" != *$'\n'* && "$1" != *$'\r'* ]]
}

timestamp() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

process_started_at() {
  ps -p "$1" -o lstart= 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

start_lock_owner_matches() {
  local owner_file="$STATE_ROOT/start.lock"
  local owner_pid owner_started owner_action actual_started command_line
  [[ -r "$owner_file" ]] || return 1
  owner_pid="$(jq -r '.pid // 0' "$owner_file" 2>/dev/null || true)"
  owner_started="$(jq -r '.processStartedAt // ""' "$owner_file" 2>/dev/null || true)"
  owner_action="$(jq -r '.action // ""' "$owner_file" 2>/dev/null || true)"
  [[ "$owner_action" =~ ^(start|cancel)$ ]] || return 1
  is_uint "$owner_pid" || return 1
  ((owner_pid > 1)) || return 1
  actual_started="$(process_started_at "$owner_pid")"
  [[ -n "$actual_started" && "$actual_started" == "$owner_started" ]] || return 1
  command_line="$(ps -ww -p "$owner_pid" -o command= 2>/dev/null || true)"
  [[ "$command_line" == *"$SCRIPT_PATH $owner_action"* ]]
}

release_start_lock() {
  local owner_file="$STATE_ROOT/start.lock"
  local owner_pid owner_started owner_action
  [[ "$START_LOCK_HELD" == "true" ]] || return 0
  owner_pid="$(jq -r '.pid // 0' "$owner_file" 2>/dev/null || true)"
  owner_started="$(jq -r '.processStartedAt // ""' "$owner_file" 2>/dev/null || true)"
  owner_action="$(jq -r '.action // ""' "$owner_file" 2>/dev/null || true)"
  if [[ "$owner_pid" == "$$" && "$owner_started" == "$START_LOCK_STARTED_AT" && "$owner_action" == "$START_LOCK_ACTION" ]]; then
    rm -f -- "$owner_file"
  fi
  START_LOCK_HELD=false
}

acquire_start_lock() {
  local lock_action="$1"
  local stale_lock attempt=0 candidate_lock="$STATE_ROOT/start.lock.candidate.$$"
  [[ "$lock_action" =~ ^(start|cancel)$ ]] || return 1
  START_LOCK_STARTED_AT="$(process_started_at $$)"
  START_LOCK_ACTION="$lock_action"
  jq -n --argjson pid "$$" --arg processStartedAt "$START_LOCK_STARTED_AT" --arg action "$lock_action" \
    '{pid: $pid, processStartedAt: $processStartedAt, action: $action}' >"$candidate_lock"
  chmod 600 "$candidate_lock"

  while ((attempt < 3)); do
    if ln "$candidate_lock" "$STATE_ROOT/start.lock" 2>/dev/null; then
      rm -f -- "$candidate_lock"
      START_LOCK_HELD=true
      trap release_start_lock EXIT
      trap 'release_start_lock; exit 129' HUP
      trap 'release_start_lock; exit 130' INT
      trap 'release_start_lock; exit 143' TERM
      return 0
    fi

    if start_lock_owner_matches; then
      rm -f -- "$candidate_lock"
      return 1
    fi
    stale_lock="$STATE_ROOT/start.lock.stale.$$.$attempt"
    if mv "$STATE_ROOT/start.lock" "$stale_lock" 2>/dev/null; then
      rm -f -- "$stale_lock"
    fi
    attempt=$((attempt + 1))
  done
  rm -f -- "$candidate_lock"
  return 1
}

atomic_state() {
  local temporary="$STATE_FILE.tmp.$$"
  mkdir -p -- "$STATE_ROOT"
  chmod 700 "$STATE_ROOT"
  cat >"$temporary"
  chmod 600 "$temporary"
  mv -f -- "$temporary" "$STATE_FILE"
}

write_state() {
  local operation_id="$1"
  local status="$2"
  local phase="$3"
  local pid_json="$4"
  local started_at="$5"
  local finished_at="$6"
  local message="$7"
  local stage_path="$8"
  local expected_sha="$9"
  local actual_sha="${10}"
  local integrity_status="${11}"
  local expected_bytes="${12}"
  local required_bytes="${13}"
  local available_bytes="${14}"
  local worker_started=""

  if [[ "$pid_json" != "null" ]] && is_uint "$pid_json" && ((pid_json > 1)); then
    worker_started="$(process_started_at "$pid_json")"
  fi

  jq -n \
    --arg operationId "$operation_id" \
    --arg status "$status" \
    --arg phase "$phase" \
    --argjson pid "$pid_json" \
    --arg processStartedAt "$worker_started" \
    --arg startedAt "$started_at" \
    --arg updatedAt "$(timestamp)" \
    --arg finishedAt "$finished_at" \
    --arg message "$message" \
    --arg modelName "$MODEL_NAME" \
    --arg modelPath "$MODEL_PATH" \
    --arg downloadTarget "$DOWNLOAD_TARGET" \
    --arg stagePath "$stage_path" \
    --arg expectedSha256 "$expected_sha" \
    --arg actualSha256 "$actual_sha" \
    --arg integrityStatus "$integrity_status" \
    --argjson expectedBytes "$expected_bytes" \
    --argjson requiredBytes "$required_bytes" \
    --argjson availableBytes "$available_bytes" \
    '{
      schemaVersion: 1,
      operationId: $operationId,
      action: "local-ai-model-install",
      status: $status,
      phase: $phase,
      pid: $pid,
      processStartedAt: (if $processStartedAt == "" then null else $processStartedAt end),
      startedAt: $startedAt,
      updatedAt: $updatedAt,
      finishedAt: (if $finishedAt == "" then null else $finishedAt end),
      message: $message,
      model: {name: $modelName, path: $modelPath, downloadTarget: $downloadTarget},
      progress: {bytesDownloaded: 0, expectedBytes: $expectedBytes, percent: 0},
      disk: {requiredBytes: $requiredBytes, availableBytes: $availableBytes},
      integrity: {
        status: $integrityStatus,
        expectedSha256: (if $expectedSha256 == "" then null else $expectedSha256 end),
        actualSha256: (if $actualSha256 == "" then null else $actualSha256 end)
      },
      stagePath: $stagePath
    }' | atomic_state
}

downloaded_bytes() {
  local stage_path="$1"
  if [[ -d "$stage_path" ]]; then
    du -sk -- "$stage_path" 2>/dev/null | awk '{printf "%.0f\n", $1 * 1024}'
  else
    printf '0\n'
  fi
}

render_status() {
  local state_json
  if [[ ! -r "$STATE_FILE" ]]; then
    jq -n '{schemaVersion: 1, operation: null}'
    return
  fi
  state_json="$(cat "$STATE_FILE")"
  if ! jq -e '.schemaVersion == 1' >/dev/null 2>&1 <<<"$state_json"; then
    jq -n '{schemaVersion: 1, operation: null}'
    return
  fi

  local stage bytes expected percent state_status pid operation_id process_started process_alive stale_worker unverifiable_worker latest_state
  state_status="$(jq -r '.status' <<<"$state_json")"
  pid="$(jq -r '.pid // 0' <<<"$state_json")"
  operation_id="$(jq -r '.operationId // ""' <<<"$state_json")"
  process_started="$(jq -r '.processStartedAt // ""' <<<"$state_json")"
  process_alive=false
  stale_worker=false
  unverifiable_worker=false
  if [[ "$state_status" == "running" ]] && worker_matches "$pid" "$operation_id" "$process_started"; then
    process_alive=true
  elif [[ "$state_status" == "running" && -z "$process_started" ]] && \
    worker_command_matches "$pid" "$operation_id"; then
    process_alive=true
    unverifiable_worker=true
  elif [[ "$state_status" == "running" ]]; then
    # The worker may have atomically published its terminal state between the
    # state read and process inspection. Re-read once before declaring it stale.
    latest_state="$(cat "$STATE_FILE")"
    if [[ "$latest_state" != "$state_json" ]] && jq -e '.schemaVersion == 1' >/dev/null 2>&1 <<<"$latest_state"; then
      state_json="$latest_state"
      state_status="$(jq -r '.status' <<<"$state_json")"
      pid="$(jq -r '.pid // 0' <<<"$state_json")"
      operation_id="$(jq -r '.operationId // ""' <<<"$state_json")"
      process_started="$(jq -r '.processStartedAt // ""' <<<"$state_json")"
    fi
    if [[ "$state_status" == "running" ]] && worker_matches "$pid" "$operation_id" "$process_started"; then
      process_alive=true
    elif [[ "$state_status" == "running" && -z "$process_started" ]] && \
      worker_command_matches "$pid" "$operation_id"; then
      process_alive=true
      unverifiable_worker=true
    elif [[ "$state_status" == "running" ]]; then
      stale_worker=true
    fi
  fi

  stage="$(jq -r '.stagePath // ""' <<<"$state_json")"
  bytes="$(downloaded_bytes "$stage")"
  expected="$(jq -r '.progress.expectedBytes // 0' <<<"$state_json")"
  is_uint "$bytes" || bytes=0
  is_uint "$expected" || expected=0
  percent=0
  if ((expected > 0)); then
    percent=$((bytes * 100 / expected))
    ((percent > 99)) && percent=99
  fi

  if [[ "$state_status" == "succeeded" ]]; then
    percent=100
    bytes="$expected"
  fi

  jq -n \
    --argjson operation "$state_json" \
    --argjson bytesDownloaded "$bytes" \
    --argjson percent "$percent" \
    --argjson processAlive "$process_alive" \
    --argjson staleWorker "$stale_worker" \
    --argjson unverifiableWorker "$unverifiable_worker" \
    --arg observedAt "$(timestamp)" \
    '{
      schemaVersion: 1,
      operation: ($operation
        | .progress.bytesDownloaded = $bytesDownloaded
        | .progress.percent = $percent
        | .processAlive = $processAlive
        | if $unverifiableWorker then
            .message = "A pre-upgrade model worker is still active; start and cancel are disabled until it exits"
          elif $staleWorker then
            .status = "failed"
            | .phase = "failed"
            | .pid = null
            | .finishedAt = $observedAt
            | .message = "The model worker is no longer running; partial data has not been removed"
            | .integrity.status = (if .integrity.status == "pending" then "notChecked" else .integrity.status end)
          else . end
      )
    }'
}

worker_command_matches() {
  local pid="$1"
  local operation_id="$2"
  local command_line
  if ! is_uint "$pid" || ((pid <= 1)) || [[ ! "$operation_id" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    return 1
  fi
  command_line="$(ps -ww -p "$pid" -o command= 2>/dev/null || true)"
  [[ "$command_line" == *"$SCRIPT_PATH __worker $operation_id "* ]]
}

worker_matches() {
  local pid="$1"
  local operation_id="$2"
  local expected_started="$3"
  local actual_started
  if ! is_uint "$pid" || ((pid <= 1)) || [[ ! "$operation_id" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || \
    [[ -z "$expected_started" ]]; then
    return 1
  fi
  actual_started="$(process_started_at "$pid")"
  [[ -n "$actual_started" && "$actual_started" == "$expected_started" ]] || return 1
  worker_command_matches "$pid" "$operation_id"
}

finalize_stale_operation() {
  local status pid operation_id process_started stage_path runner_path stored_model_path temporary
  local cleanup_message remaining_stage
  [[ -r "$STATE_FILE" ]] || return 0
  status="$(jq -r '.status // ""' "$STATE_FILE" 2>/dev/null || true)"
  [[ "$status" == "running" ]] || return 0
  pid="$(jq -r '.pid // 0' "$STATE_FILE" 2>/dev/null || true)"
  operation_id="$(jq -r '.operationId // ""' "$STATE_FILE" 2>/dev/null || true)"
  process_started="$(jq -r '.processStartedAt // ""' "$STATE_FILE" 2>/dev/null || true)"
  if [[ -z "$process_started" ]] && worker_command_matches "$pid" "$operation_id"; then
    return 1
  fi
  worker_matches "$pid" "$operation_id" "$process_started" && return 0

  stage_path="$(jq -r '.stagePath // ""' "$STATE_FILE" 2>/dev/null || true)"
  stored_model_path="$(jq -r '.model.path // ""' "$STATE_FILE" 2>/dev/null || true)"
  runner_path="$STATE_ROOT/runner-$operation_id"
  if cleanup_stage "$operation_id" "$stage_path" "$runner_path" "$stored_model_path"; then
    cleanup_message="The model worker is no longer running; partial data was removed"
    remaining_stage=""
  else
    cleanup_message="The model worker is no longer running; partial data could not be safely removed"
    remaining_stage="$stage_path"
  fi
  temporary="$STATE_FILE.tmp.$$"
  jq \
    --arg updatedAt "$(timestamp)" \
    --arg message "$cleanup_message" \
    --arg remainingStage "$remaining_stage" \
    '.status = "failed"
      | .phase = "failed"
      | .pid = null
      | .updatedAt = $updatedAt
      | .finishedAt = $updatedAt
      | .message = $message
      | .integrity.status = (if .integrity.status == "pending" then "notChecked" else .integrity.status end)
      | .stagePath = $remainingStage' \
    "$STATE_FILE" >"$temporary"
  chmod 600 "$temporary"
  mv -f -- "$temporary" "$STATE_FILE"
}

cleanup_stage() {
  local operation_id="$1"
  local stage_path="$2"
  local runner_path="$3"
  local model_path="$4"
  local model_parent cleanup_complete=true
  if ! valid_path "$model_path"; then
    return 1
  fi
  model_parent="$(dirname "$model_path")"

  if [[ "$operation_id" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] && \
    [[ "$stage_path" == "$model_parent/.nix-me-model-$operation_id" ]]; then
    rm -rf -- "$stage_path" || cleanup_complete=false
  elif [[ -n "$stage_path" ]]; then
    cleanup_complete=false
  fi
  if [[ "$operation_id" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] && \
    [[ "$runner_path" == "$STATE_ROOT/runner-$operation_id" ]]; then
    rm -rf -- "$runner_path" || cleanup_complete=false
  elif [[ -n "$runner_path" ]]; then
    cleanup_complete=false
  fi
  [[ "$cleanup_complete" == "true" && ! -e "$stage_path" && ! -e "$runner_path" ]]
}

sha256_file() {
  local path="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
  else
    shasum -a 256 "$path" | awk '{print $1}'
  fi
}

find_downloaded_model() {
  local stage_path="$1"
  local runner_path="$2"
  local linked candidate canonical_stage canonical_candidate

  if [[ -L "$runner_path/ds4flash.gguf" ]]; then
    linked="$(readlink "$runner_path/ds4flash.gguf")"
    if [[ "$linked" == /* ]]; then
      candidate="$linked"
    else
      candidate="$runner_path/$linked"
    fi
    if [[ -f "$candidate" ]]; then
      canonical_stage="$(cd "$stage_path" && pwd -P)"
      canonical_candidate="$(cd "$(dirname "$candidate")" && pwd -P)/$(basename "$candidate")"
      if [[ "$canonical_candidate" == "$canonical_stage/"* ]]; then
        printf '%s\n' "$canonical_candidate"
        return 0
      fi
    fi
  fi

  candidate="$(find "$stage_path" -type f ! -name '*.part' ! -name '*.aria2' -size +0c -print 2>/dev/null | head -1)"
  if [[ -n "$candidate" ]] && [[ "$(find "$stage_path" -type f ! -name '*.part' ! -name '*.aria2' -size +0c -print 2>/dev/null | wc -l | tr -d ' ')" == "1" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi
  return 1
}

worker() {
  local operation_id="$1" stage_path="$2" runner_path="$3" started_at="$4"
  local expected_sha="$5" expected_bytes="$6" required_bytes="$7" available_bytes="$8"
  local child_pid=0 cancelled=false exit_code=0 candidate actual_sha="" integrity_status

  on_cancel() {
    cancelled=true
    if ((child_pid > 1)); then
      pkill -TERM -P "$child_pid" >/dev/null 2>&1 || true
      kill -TERM "$child_pid" >/dev/null 2>&1 || true
    fi
  }

  finish_cancelled() {
    cleanup_stage "$operation_id" "$stage_path" "$runner_path" "$MODEL_PATH" || true
    write_state "$operation_id" cancelled cancelled null "$started_at" "$(timestamp)" \
      "Model download cancelled; partial data was removed" "" "$expected_sha" "" notChecked \
      "$expected_bytes" "$required_bytes" "$available_bytes"
    exit 0
  }
  trap on_cancel TERM INT

  write_state "$operation_id" running downloading "$$" "$started_at" "" \
    "Downloading $MODEL_NAME" "$stage_path" "$expected_sha" "" pending \
    "$expected_bytes" "$required_bytes" "$available_bytes"

  mkdir -p -- "$stage_path" "$runner_path"
  chmod 700 "$stage_path" "$runner_path"
  cp -- "$DOWNLOAD_PROGRAM" "$runner_path/download_model.sh"
  chmod 700 "$runner_path/download_model.sh"

  DS4_GGUF_DIR="$stage_path" "$runner_path/download_model.sh" "$DOWNLOAD_TARGET" >>"$LOG_FILE" 2>&1 &
  child_pid=$!
  set +e
  wait "$child_pid"
  exit_code=$?
  set -e
  child_pid=0

  if [[ "$cancelled" == "true" ]]; then
    finish_cancelled
  fi

  if ((exit_code != 0)); then
    local failure_message
    failure_message="$(tail -1 "$LOG_FILE" 2>/dev/null || true)"
    cleanup_stage "$operation_id" "$stage_path" "$runner_path" "$MODEL_PATH" || true
    write_state "$operation_id" failed failed null "$started_at" "$(timestamp)" \
      "${failure_message:-The model downloader failed}" "" "$expected_sha" "" notChecked \
      "$expected_bytes" "$required_bytes" "$available_bytes"
    exit 0
  fi

  if ! candidate="$(find_downloaded_model "$stage_path" "$runner_path")"; then
    cleanup_stage "$operation_id" "$stage_path" "$runner_path" "$MODEL_PATH" || true
    write_state "$operation_id" failed failed null "$started_at" "$(timestamp)" \
      "The downloader completed without one identifiable model artifact" "" "$expected_sha" "" notChecked \
      "$expected_bytes" "$required_bytes" "$available_bytes"
    exit 0
  fi
  [[ "$cancelled" == "true" ]] && finish_cancelled

  integrity_status=notProvided
  if [[ -n "$expected_sha" ]]; then
    write_state "$operation_id" running verifying "$$" "$started_at" "" \
      "Verifying SHA-256 integrity" "$stage_path" "$expected_sha" "" pending \
      "$expected_bytes" "$required_bytes" "$available_bytes"
    local checksum_file="$runner_path/model.sha256"
    sha256_file "$candidate" >"$checksum_file" &
    child_pid=$!
    set +e
    wait "$child_pid"
    exit_code=$?
    set -e
    child_pid=0
    [[ "$cancelled" == "true" ]] && finish_cancelled
    if ((exit_code != 0)); then
      cleanup_stage "$operation_id" "$stage_path" "$runner_path" "$MODEL_PATH" || true
      write_state "$operation_id" failed failed null "$started_at" "$(timestamp)" \
        "The model checksum could not be calculated" "" "$expected_sha" "" notChecked \
        "$expected_bytes" "$required_bytes" "$available_bytes"
      exit 0
    fi
    actual_sha="$(tr -d '[:space:]' <"$checksum_file")"
    if [[ "$actual_sha" != "$expected_sha" ]]; then
      cleanup_stage "$operation_id" "$stage_path" "$runner_path" "$MODEL_PATH" || true
      write_state "$operation_id" failed failed null "$started_at" "$(timestamp)" \
        "Checksum mismatch; the downloaded model was not installed" "" "$expected_sha" "$actual_sha" mismatch \
        "$expected_bytes" "$required_bytes" "$available_bytes"
      exit 0
    fi
    integrity_status=verified
  fi

  write_state "$operation_id" running installing "$$" "$started_at" "" \
    "Installing the verified model atomically" "$stage_path" "$expected_sha" "$actual_sha" "$integrity_status" \
    "$expected_bytes" "$required_bytes" "$available_bytes"
  [[ "$cancelled" == "true" ]] && finish_cancelled

  local pending_install="${MODEL_PATH}.nix-me-install-${operation_id}"
  if ! mv -- "$candidate" "$pending_install"; then
    cleanup_stage "$operation_id" "$stage_path" "$runner_path" "$MODEL_PATH" || true
    write_state "$operation_id" failed failed null "$started_at" "$(timestamp)" \
      "The completed model could not be staged for installation" "" "$expected_sha" "$actual_sha" "$integrity_status" \
      "$expected_bytes" "$required_bytes" "$available_bytes"
    exit 0
  fi

  # Once the candidate is staged beside the destination, the final rename is
  # the operation's atomic commit point and is intentionally non-interruptible.
  trap '' TERM INT
  if [[ "$cancelled" == "true" ]]; then
    rm -f -- "$pending_install"
    finish_cancelled
  fi
  if ! mv -f -- "$pending_install" "$MODEL_PATH"; then
    rm -f -- "$pending_install"
    cleanup_stage "$operation_id" "$stage_path" "$runner_path" "$MODEL_PATH" || true
    write_state "$operation_id" failed failed null "$started_at" "$(timestamp)" \
      "The completed model could not be installed" "" "$expected_sha" "$actual_sha" "$integrity_status" \
      "$expected_bytes" "$required_bytes" "$available_bytes"
    exit 0
  fi

  cleanup_stage "$operation_id" "$stage_path" "$runner_path" "$MODEL_PATH" || true
  write_state "$operation_id" succeeded completed null "$started_at" "$(timestamp)" \
    "Model installed successfully" "" "$expected_sha" "$actual_sha" "$integrity_status" \
    "$expected_bytes" "$required_bytes" "$available_bytes"
}

start_operation() {
  local payload request_sha configured_sha expected_sha expected_bytes required_bytes available_kib available_bytes
  local operation_id started_at model_parent stage_path runner_path worker_pid worker_started state_process_started current_status current_pid current_operation_id current_process_started

  payload="$(cat)"
  [[ -n "$payload" ]] || payload='{}'
  if ! jq -e 'type == "object" and (keys - ["expectedSha256"] | length == 0)' >/dev/null 2>&1 <<<"$payload"; then
    fail_json invalid_request "The model request must contain only expectedSha256"
    return 65
  fi
  request_sha="$(jq -r '.expectedSha256 // ""' <<<"$payload")"
  configured_sha="${LOCAL_AI_EXPECTED_SHA256:-}"
  if [[ -n "$request_sha" ]]; then
    request_sha="$(printf '%s' "$request_sha" | tr '[:upper:]' '[:lower:]')"
    if [[ ! "$request_sha" =~ ^[0-9a-f]{64}$ ]]; then
      fail_json invalid_checksum "expectedSha256 must contain exactly 64 hexadecimal characters"
      return 65
    fi
  fi
  if [[ -n "$configured_sha" ]]; then
    configured_sha="$(printf '%s' "$configured_sha" | tr '[:upper:]' '[:lower:]')"
    if [[ ! "$configured_sha" =~ ^[0-9a-f]{64}$ ]]; then
      fail_json invalid_configuration "The configured local-AI checksum is invalid"
      return 78
    fi
  fi
  if [[ -n "$configured_sha" && -n "$request_sha" && "$configured_sha" != "$request_sha" ]]; then
    fail_json checksum_conflict "The requested checksum does not match the profile-configured checksum"
    return 65
  fi
  expected_sha="${configured_sha:-$request_sha}"

  if ! valid_path "$MODEL_PATH" || ! valid_path "$DOWNLOAD_PROGRAM" || \
    [[ ! "$DOWNLOAD_TARGET" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || \
    ! is_uint "$DOWNLOAD_SIZE_GIB" || ! is_uint "$REQUIRED_FREE_GIB"; then
    fail_json invalid_configuration "The local-AI model configuration failed validation"
    return 78
  fi
  if [[ ! -r "$DOWNLOAD_PROGRAM" ]]; then
    fail_json missing_downloader "The configured DS4 downloader is unavailable"
    return 69
  fi

  mkdir -p -- "$STATE_ROOT"
  chmod 700 "$STATE_ROOT"
  if ! acquire_start_lock start; then
    fail_json operation_busy "Another model action is starting"
    return 75
  fi

  if [[ -r "$STATE_FILE" ]]; then
    current_status="$(jq -r '.status // ""' "$STATE_FILE" 2>/dev/null || true)"
    current_pid="$(jq -r '.pid // 0' "$STATE_FILE" 2>/dev/null || true)"
    current_operation_id="$(jq -r '.operationId // ""' "$STATE_FILE" 2>/dev/null || true)"
    current_process_started="$(jq -r '.processStartedAt // ""' "$STATE_FILE" 2>/dev/null || true)"
    if [[ "$current_status" == "running" ]]; then
      if [[ -z "$current_process_started" ]] && worker_command_matches "$current_pid" "$current_operation_id"; then
        release_start_lock
        fail_json operation_identity_unavailable \
          "A pre-upgrade model operation is still active; wait for it to finish before starting another"
        return 75
      fi
      if worker_matches "$current_pid" "$current_operation_id" "$current_process_started"; then
        release_start_lock
        fail_json operation_busy "A model operation is already running"
        return 75
      fi
      finalize_stale_operation
    fi
  fi

  model_parent="$(dirname "$MODEL_PATH")"
  mkdir -p -- "$model_parent"
  available_kib="${LOCAL_AI_AVAILABLE_KIB:-$(df -Pk "$model_parent" | awk 'NR == 2 {print $4}')}"
  is_uint "$available_kib" || available_kib=0
  available_bytes=$((available_kib * 1024))
  required_bytes=$((REQUIRED_FREE_GIB * 1024 * 1024 * 1024))
  expected_bytes=$((DOWNLOAD_SIZE_GIB * 1024 * 1024 * 1024))
  operation_id="$(date -u '+%Y%m%dT%H%M%SZ')-$$-${RANDOM:-0}"
  started_at="$(timestamp)"
  stage_path="$model_parent/.nix-me-model-$operation_id"
  runner_path="$STATE_ROOT/runner-$operation_id"

  if ((available_bytes < required_bytes)); then
    write_state "$operation_id" failed preflight null "$started_at" "$(timestamp)" \
      "Insufficient disk space for the model download" "" "$expected_sha" "" notChecked \
      "$expected_bytes" "$required_bytes" "$available_bytes"
    release_start_lock
    render_status
    return 0
  fi

  : >"$LOG_FILE"
  chmod 600 "$LOG_FILE"
  nohup "$SCRIPT_PATH" __worker "$operation_id" "$stage_path" "$runner_path" "$started_at" \
    "$expected_sha" "$expected_bytes" "$required_bytes" "$available_bytes" \
    >>"$LOG_FILE" 2>&1 </dev/null &
  worker_pid=$!
  worker_started=""

  local identity_attempt=0
  while [[ -z "$worker_started" ]] && ((identity_attempt < 25)) && kill -0 "$worker_pid" 2>/dev/null; do
    worker_started="$(process_started_at "$worker_pid")"
    [[ -n "$worker_started" ]] || sleep 0.02
    identity_attempt=$((identity_attempt + 1))
  done

  local attempt=0 state_pid=0
  while ((attempt < 100)); do
    state_pid="$(jq -r '.pid // 0' "$STATE_FILE" 2>/dev/null || printf 0)"
    current_operation_id="$(jq -r '.operationId // ""' "$STATE_FILE" 2>/dev/null || true)"
    state_process_started="$(jq -r '.processStartedAt // ""' "$STATE_FILE" 2>/dev/null || true)"
    [[ "$state_pid" == "$worker_pid" && "$current_operation_id" == "$operation_id" && \
      "$state_process_started" == "$worker_started" && -n "$worker_started" ]] && break
    worker_matches "$worker_pid" "$operation_id" "$worker_started" || break
    sleep 0.02
    attempt=$((attempt + 1))
  done
  release_start_lock
  if [[ "$state_pid" != "$worker_pid" || "$current_operation_id" != "$operation_id" || \
    "$state_process_started" != "$worker_started" || -z "$worker_started" ]]; then
    if worker_matches "$worker_pid" "$operation_id" "$worker_started"; then
      kill -TERM "$worker_pid" 2>/dev/null || true
    fi
    cleanup_stage "$operation_id" "$stage_path" "$runner_path" "$MODEL_PATH" || true
    write_state "$operation_id" failed failed null "$started_at" "$(timestamp)" \
      "The model worker could not initialize" "" "$expected_sha" "" notChecked \
      "$expected_bytes" "$required_bytes" "$available_bytes"
  fi
  render_status
}

cancel_operation() {
  local status pid operation_id process_started attempt
  mkdir -p -- "$STATE_ROOT"
  chmod 700 "$STATE_ROOT"
  if ! acquire_start_lock cancel; then
    fail_json operation_busy "Another model action is in progress"
    return 75
  fi
  if [[ ! -r "$STATE_FILE" ]]; then
    release_start_lock
    fail_json no_operation "There is no model operation to cancel"
    return 0
  fi
  status="$(jq -r '.status // ""' "$STATE_FILE" 2>/dev/null || true)"
  pid="$(jq -r '.pid // 0' "$STATE_FILE" 2>/dev/null || true)"
  operation_id="$(jq -r '.operationId // ""' "$STATE_FILE" 2>/dev/null || true)"
  process_started="$(jq -r '.processStartedAt // ""' "$STATE_FILE" 2>/dev/null || true)"
  if [[ "$status" == "running" && -z "$process_started" ]] && worker_command_matches "$pid" "$operation_id"; then
    release_start_lock
    fail_json operation_identity_unavailable \
      "A pre-upgrade model operation is still active and cannot be cancelled safely; wait for it to finish"
    return 75
  fi
  if [[ "$status" != "running" ]] || ! worker_matches "$pid" "$operation_id" "$process_started"; then
    if [[ "$status" == "running" ]]; then
      finalize_stale_operation
    fi
    release_start_lock
    render_status
    return 0
  fi

  kill -TERM "$pid"
  attempt=0
  while ((attempt < 100)) && worker_matches "$pid" "$operation_id" "$process_started"; do
    sleep 0.05
    attempt=$((attempt + 1))
  done
  release_start_lock
  render_status
}

if ! command -v jq >/dev/null 2>&1; then
  printf '{"schemaVersion":1,"error":{"code":"missing_dependency","message":"jq is required by local-ai-model"}}\n'
  exit 69
fi

case "${1:-}" in
  start) start_operation ;;
  status) render_status ;;
  cancel) cancel_operation ;;
  __worker)
    shift
    set -e
    worker "$@"
    ;;
  -h | --help | help) usage ;;
  *)
    usage >&2
    fail_json unknown_action "Unknown local-AI model action: ${1:-}"
    exit 64
    ;;
esac
