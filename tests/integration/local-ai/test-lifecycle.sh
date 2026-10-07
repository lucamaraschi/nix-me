#!/bin/bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
lifecycle="$repo_dir/tools/local-ai/model-lifecycle.sh"
fake_downloader="$repo_dir/tests/integration/local-ai/fake-downloader.sh"
fake_sha256sum="$repo_dir/tests/integration/local-ai/fake-sha256sum.sh"
temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/nix-me-local-ai-lifecycle.XXXXXX")"
trap 'rm -rf "$temp_dir"' EXIT

fail() {
  echo "local AI lifecycle test failed: $*" >&2
  exit 1
}

new_case() {
  local name="$1"
  case_home="$temp_dir/$name/home"
  case_state="$temp_dir/$name/state"
  case_model="$temp_dir/$name/model/ds4flash.gguf"
  case_log="$temp_dir/$name/downloader.log"
  mkdir -p "$(dirname "$case_model")" "$case_home"
  printf 'old-model' >"$case_model"
}

run_lifecycle() {
  env \
    HOME="$case_home" \
    LOCAL_AI_OPERATION_DIR="$case_state" \
    LOCAL_AI_MODEL_PATH="$case_model" \
    LOCAL_AI_DOWNLOAD_PROGRAM="$fake_downloader" \
    LOCAL_AI_DOWNLOAD_SIZE_GIB="${LOCAL_AI_DOWNLOAD_SIZE_GIB:-0}" \
    LOCAL_AI_REQUIRED_FREE_DISK_GIB="${LOCAL_AI_REQUIRED_FREE_DISK_GIB:-0}" \
    LOCAL_AI_AVAILABLE_KIB="${LOCAL_AI_AVAILABLE_KIB:-1048576}" \
    LOCAL_AI_EXPECTED_SHA256="${LOCAL_AI_EXPECTED_SHA256:-}" \
    FAKE_DOWNLOAD_MODE="${FAKE_DOWNLOAD_MODE:-success}" \
    FAKE_DOWNLOAD_LOG="$case_log" \
    FAKE_MODEL_CONTENT="${FAKE_MODEL_CONTENT:-model-data}" \
    FAKE_SHA256_MARKER="${FAKE_SHA256_MARKER:-}" \
    "$lifecycle" "$@"
}

run_cli() {
  env \
    HOME="$case_home" \
    LOCAL_AI_OPERATION_DIR="$case_state" \
    LOCAL_AI_MODEL_PATH="$case_model" \
    LOCAL_AI_DOWNLOAD_PROGRAM="$fake_downloader" \
    LOCAL_AI_DOWNLOAD_SIZE_GIB=0 \
    LOCAL_AI_REQUIRED_FREE_DISK_GIB=0 \
    LOCAL_AI_AVAILABLE_KIB=1048576 \
    NIX_ME_LOCAL_AI_MODEL_BIN="$lifecycle" \
    FAKE_DOWNLOAD_MODE="${FAKE_DOWNLOAD_MODE:-success}" \
    FAKE_DOWNLOAD_LOG="$case_log" \
    FAKE_MODEL_CONTENT="${FAKE_MODEL_CONTENT:-model-data}" \
    "$repo_dir/apps/cli/bin/nix-me" local-ai model "$@"
}

wait_for_terminal_state() {
  local output status attempt=0
  while ((attempt < 200)); do
    output="$(run_lifecycle status)"
    status="$(jq -r '.operation.status // "none"' <<<"$output")"
    if [[ "$status" != "running" ]]; then
      printf '%s\n' "$output"
      return 0
    fi
    sleep 0.05
    attempt=$((attempt + 1))
  done
  fail "operation did not reach a terminal state"
}

assert_no_partial_data() {
  if find "$(dirname "$case_model")" -maxdepth 1 -name '.nix-me-model-*' -print -quit | grep -q .; then
    fail "partial model staging data remains"
  fi
  if find "$case_state" -maxdepth 1 -name 'runner-*' -print -quit 2>/dev/null | grep -q .; then
    fail "temporary downloader runner remains"
  fi
}

# Successful verified install atomically replaces the previous model.
new_case success
expected_sha="$(printf 'model-data' | shasum -a 256 | awk '{print $1}')"
printf '{"expectedSha256":"%s"}\n' "$expected_sha" | run_lifecycle start >"$temp_dir/success-start.json"
success_result="$(wait_for_terminal_state)"
jq -e '
  .operation.status == "succeeded" and
  .operation.phase == "completed" and
  .operation.integrity.status == "verified" and
  .operation.progress.percent == 100
' <<<"$success_result" >/dev/null
[[ "$(cat "$case_model")" == "model-data" ]] || fail "successful install did not replace the model"
assert_no_partial_data

# State and log files are private.
file_mode() {
  if stat -f '%Lp' "$1" >/dev/null 2>&1; then
    stat -f '%Lp' "$1"
  else
    stat -c '%a' "$1"
  fi
}

state_mode="$(file_mode "$case_state/state.json")"
root_mode="$(file_mode "$case_state")"
[[ "$state_mode" == "600" && "$root_mode" == "700" ]] || fail "operation files are not private"

# Missing checksum is reported honestly rather than treated as verified.
new_case no-checksum
run_cli start >"$temp_dir/no-checksum-start.json"
no_checksum_result="$(wait_for_terminal_state)"
jq -e '.operation.status == "succeeded" and .operation.integrity.status == "notProvided"' \
  <<<"$no_checksum_result" >/dev/null

# Disk preflight fails before invoking the downloader.
new_case insufficient-disk
LOCAL_AI_REQUIRED_FREE_DISK_GIB=1 LOCAL_AI_AVAILABLE_KIB=1 \
  run_lifecycle start <<<'{}' >"$temp_dir/insufficient.json"
jq -e '
  .operation.status == "failed" and
  .operation.phase == "preflight" and
  (.operation.disk.availableBytes < .operation.disk.requiredBytes)
' "$temp_dir/insufficient.json" >/dev/null
[[ ! -e "$case_log" ]] || fail "downloader ran after a failed disk preflight"
[[ "$(cat "$case_model")" == "old-model" ]] || fail "disk preflight changed the installed model"

# A checksum mismatch rejects the candidate and preserves the valid model.
new_case checksum-mismatch
printf '{"expectedSha256":"%064d"}\n' 0 | run_lifecycle start >"$temp_dir/mismatch-start.json"
mismatch_result="$(wait_for_terminal_state)"
jq -e '.operation.status == "failed" and .operation.integrity.status == "mismatch"' \
  <<<"$mismatch_result" >/dev/null
[[ "$(cat "$case_model")" == "old-model" ]] || fail "checksum mismatch replaced the valid model"
assert_no_partial_data

# A profile-configured checksum is enforced when GUI/CLI callers omit it.
new_case configured-checksum
LOCAL_AI_EXPECTED_SHA256="$(printf '%064d' 0)" run_lifecycle start <<<'{}' \
  >"$temp_dir/configured-checksum-start.json"
configured_checksum_result="$(wait_for_terminal_state)"
jq -e '
  .operation.status == "failed" and
  .operation.integrity.status == "mismatch" and
  .operation.integrity.expectedSha256 == ("0" * 64)
' <<<"$configured_checksum_result" >/dev/null
[[ "$(cat "$case_model")" == "old-model" ]] || fail "configured checksum mismatch replaced the valid model"
assert_no_partial_data

# A request cannot override the checksum trusted by the host profile.
new_case checksum-override
configured_sha="$(printf 'model-data' | shasum -a 256 | awk '{print $1}')"
if LOCAL_AI_EXPECTED_SHA256="$configured_sha" run_lifecycle start <<<'{"expectedSha256":"0000000000000000000000000000000000000000000000000000000000000000"}' \
  >"$temp_dir/checksum-override.json"; then
  fail "caller checksum unexpectedly overrode the configured checksum"
else
  checksum_override_status=$?
fi
[[ "$checksum_override_status" == "65" ]] || fail "checksum override returned $checksum_override_status"
jq -e '.error.code == "checksum_conflict"' "$temp_dir/checksum-override.json" >/dev/null
[[ ! -e "$case_log" ]] || fail "downloader ran after a checksum conflict"
[[ "$(cat "$case_model")" == "old-model" ]] || fail "checksum conflict changed the installed model"

# Cancellation terminates the downloader and removes its partial artifact.
new_case cancellation
FAKE_DOWNLOAD_MODE=slow run_lifecycle start <<<'{}' >"$temp_dir/cancel-start.json"
attempt=0
while [[ ! -s "$case_log" && $attempt -lt 100 ]]; do
  sleep 0.05
  attempt=$((attempt + 1))
done
FAKE_DOWNLOAD_MODE=slow run_lifecycle cancel >"$temp_dir/cancel.json"
cancel_result="$(wait_for_terminal_state)"
jq -e '.operation.status == "cancelled" and .operation.phase == "cancelled"' \
  <<<"$cancel_result" >/dev/null
[[ "$(cat "$case_model")" == "old-model" ]] || fail "cancellation replaced the valid model"
assert_no_partial_data

# Verification is a cancellable child phase and cannot install after cancellation.
new_case cancellation-during-verification
fake_bin="$temp_dir/cancellation-during-verification/bin"
verify_marker="$temp_dir/cancellation-during-verification/verifying"
mkdir -p "$fake_bin"
ln -s "$fake_sha256sum" "$fake_bin/sha256sum"
PATH="$fake_bin:$PATH" \
FAKE_SHA256_MARKER="$verify_marker" \
  run_lifecycle start <<<"$(printf '{\"expectedSha256\":\"%s\"}' "$expected_sha")" \
  >"$temp_dir/verify-cancel-start.json"
attempt=0
while [[ ! -s "$verify_marker" && $attempt -lt 100 ]]; do
  sleep 0.05
  attempt=$((attempt + 1))
done
[[ -s "$verify_marker" ]] || fail "operation never entered checksum verification"
PATH="$fake_bin:$PATH" \
FAKE_SHA256_MARKER="$verify_marker" \
  run_lifecycle cancel >"$temp_dir/verify-cancel.json"
verify_cancel_result="$(wait_for_terminal_state)"
jq -e '.operation.status == "cancelled" and .operation.phase == "cancelled"' \
  <<<"$verify_cancel_result" >/dev/null
[[ "$(cat "$case_model")" == "old-model" ]] || fail "verification cancellation installed the candidate"
assert_no_partial_data

# A still-running operation from the pre-identity schema is never signalled or
# cleaned until its matching worker exits.
new_case legacy-active-worker
legacy_operation_id="legacy-operation"
legacy_stage="$(dirname "$case_model")/.nix-me-model-$legacy_operation_id"
legacy_runner="$case_state/runner-$legacy_operation_id"
mkdir -p "$legacy_stage" "$legacy_runner"
printf 'partial' >"$legacy_stage/model.gguf.part"
printf 'runner' >"$legacy_runner/download_model.sh"
bash -c 'while true; do sleep 1; done' "$lifecycle" __worker "$legacy_operation_id" fixture &
legacy_pid=$!
mkdir -p "$case_state"
jq -n \
  --arg operationId "$legacy_operation_id" \
  --argjson pid "$legacy_pid" \
  --arg modelPath "$case_model" \
  --arg stagePath "$legacy_stage" \
  '{
    schemaVersion: 1, operationId: $operationId, action: "local-ai-model-install",
    status: "running", phase: "downloading", pid: $pid,
    startedAt: "2026-10-05T20:00:00Z", updatedAt: "2026-10-05T20:00:01Z", finishedAt: null,
    message: "Downloading", model: {name:"Test",path:$modelPath,downloadTarget:"ds4f-q2"},
    progress: {bytesDownloaded:0,expectedBytes:10,percent:0},
    disk: {requiredBytes:0,availableBytes:100},
    integrity: {status:"pending",expectedSha256:null,actualSha256:null},
    stagePath: $stagePath
  }' >"$case_state/state.json"
chmod 600 "$case_state/state.json"
run_lifecycle status >"$temp_dir/legacy-status.json"
jq -e '
  .operation.status == "running" and
  .operation.processAlive == true and
  (.operation.message | contains("pre-upgrade model worker"))
' "$temp_dir/legacy-status.json" >/dev/null
if run_lifecycle start <<<'{}' >"$temp_dir/legacy-start.json"; then
  fail "start accepted an active pre-upgrade operation"
else
  legacy_start_status=$?
fi
[[ "$legacy_start_status" == "75" ]] || fail "legacy start returned $legacy_start_status"
jq -e '.error.code == "operation_identity_unavailable"' "$temp_dir/legacy-start.json" >/dev/null
if run_lifecycle cancel >"$temp_dir/legacy-cancel.json"; then
  fail "cancel accepted an unverifiable pre-upgrade operation"
else
  legacy_cancel_status=$?
fi
[[ "$legacy_cancel_status" == "75" ]] || fail "legacy cancel returned $legacy_cancel_status"
jq -e '.error.code == "operation_identity_unavailable"' "$temp_dir/legacy-cancel.json" >/dev/null
kill -0 "$legacy_pid" 2>/dev/null || fail "legacy mutation signalled the active worker"
[[ -e "$legacy_stage/model.gguf.part" && -e "$legacy_runner/download_model.sh" ]] || \
  fail "legacy mutation cleaned active operation data"
kill "$legacy_pid"
wait "$legacy_pid" 2>/dev/null || true
run_lifecycle cancel >"$temp_dir/legacy-cleanup.json"
jq -e '.operation.status == "failed" and (.operation.message | contains("partial data was removed"))' \
  "$temp_dir/legacy-cleanup.json" >/dev/null
assert_no_partial_data

# Even a matching command line is not trusted when its process identity differs.
new_case stale-worker
stale_operation_id="stale-operation"
stale_stage="$(dirname "$case_model")/.nix-me-model-$stale_operation_id"
stale_runner="$case_state/runner-$stale_operation_id"
mkdir -p "$stale_stage" "$stale_runner"
printf 'partial' >"$stale_stage/model.gguf.part"
printf 'runner' >"$stale_runner/download_model.sh"
bash -c 'while true; do sleep 1; done' "$lifecycle" __worker "$stale_operation_id" fixture &
unrelated_pid=$!
unrelated_command="$(ps -ww -p "$unrelated_pid" -o command= 2>/dev/null || true)"
[[ "$unrelated_command" == *"$lifecycle __worker $stale_operation_id "* ]] || \
  fail "stale-worker fixture does not have the expected matching command line"
mkdir -p "$case_state"
jq -n \
  --arg operationId "$stale_operation_id" \
  --argjson pid "$unrelated_pid" \
  --arg modelPath "$case_model" \
  --arg stagePath "$stale_stage" \
  '{
    schemaVersion: 1, operationId: $operationId, action: "local-ai-model-install",
    status: "running", phase: "downloading", pid: $pid, processStartedAt: "not-the-real-start-time",
    startedAt: "2026-10-05T20:00:00Z", updatedAt: "2026-10-05T20:00:01Z", finishedAt: null,
    message: "Downloading", model: {name:"Test",path:$modelPath,downloadTarget:"ds4f-q2"},
    progress: {bytesDownloaded:0,expectedBytes:10,percent:0},
    disk: {requiredBytes:0,availableBytes:100},
    integrity: {status:"pending",expectedSha256:null,actualSha256:null},
    stagePath: $stagePath
  }' >"$case_state/state.json"
chmod 600 "$case_state/state.json"
state_hash_before="$(shasum -a 256 "$case_state/state.json" | awk '{print $1}')"
state_stat_before="$(stat -f '%m:%c:%z' "$case_state/state.json" 2>/dev/null || stat -c '%Y:%Z:%s' "$case_state/state.json")"
run_lifecycle status >"$temp_dir/stale-worker-status.json"
jq -e '
  .operation.status == "failed" and
  .operation.phase == "failed" and
  .operation.processAlive == false and
  (.operation.message | contains("partial data has not been removed"))
' "$temp_dir/stale-worker-status.json" >/dev/null
state_hash_after="$(shasum -a 256 "$case_state/state.json" | awk '{print $1}')"
state_stat_after="$(stat -f '%m:%c:%z' "$case_state/state.json" 2>/dev/null || stat -c '%Y:%Z:%s' "$case_state/state.json")"
[[ "$state_hash_before" == "$state_hash_after" ]] || fail "status rewrote stale operation state"
[[ "$state_stat_before" == "$state_stat_after" ]] || fail "status changed stale operation metadata"
[[ -e "$stale_stage/model.gguf.part" && -e "$stale_runner/download_model.sh" ]] || \
  fail "status cleaned stale partial data"
kill -0 "$unrelated_pid" 2>/dev/null || fail "status signalled an unrelated reused PID"
[[ "$(cat "$case_model")" == "old-model" ]] || fail "status changed the installed model"

run_lifecycle cancel >"$temp_dir/stale-worker-cancel.json"
jq -e '
  .operation.status == "failed" and
  .operation.phase == "failed" and
  .operation.processAlive == false and
  (.operation.message | contains("partial data was removed"))
' "$temp_dir/stale-worker-cancel.json" >/dev/null
kill -0 "$unrelated_pid" 2>/dev/null || fail "explicit stale cleanup signalled an unrelated reused PID"
kill "$unrelated_pid"
wait "$unrelated_pid" 2>/dev/null || true
[[ "$(cat "$case_model")" == "old-model" ]] || fail "stale recovery changed the installed model"
assert_no_partial_data

# An interrupted prior start cannot leave a permanent lock.
new_case stale-lock
mkdir -p "$case_state"
printf '{"pid":999999,"processStartedAt":"stale"}\n' >"$case_state/start.lock"
run_lifecycle start <<<'{}' >"$temp_dir/stale-lock-start.json"
stale_lock_result="$(wait_for_terminal_state)"
jq -e '.operation.status == "succeeded"' <<<"$stale_lock_result" >/dev/null
[[ ! -e "$case_state/start.lock" ]] || fail "stale start lock was not recovered"
[[ "$(cat "$case_model")" == "model-data" ]] || fail "stale lock recovery changed install semantics"
assert_no_partial_data

# Downloader failures clean staging data and retain the previous model.
new_case failure
FAKE_DOWNLOAD_MODE=fail run_lifecycle start <<<'{}' >"$temp_dir/failure-start.json"
failure_result="$(wait_for_terminal_state)"
jq -e '.operation.status == "failed" and (.operation.message | contains("fake downloader failure"))' \
  <<<"$failure_result" >/dev/null
[[ "$(cat "$case_model")" == "old-model" ]] || fail "failed download replaced the valid model"
assert_no_partial_data

# The read-only management refresh must never invoke the configured downloader.
new_case read-only-refresh
NIX_ME_CONFIG_DIR="$repo_dir" \
NIX_ME_SKIP_UPDATES=1 \
NIX_ME_LOCAL_AI_STATUS="$repo_dir/packages/management-api/test/fixtures/local-ai-status-degraded-v1.json" \
LOCAL_AI_DOWNLOAD_PROGRAM="$fake_downloader" \
FAKE_DOWNLOAD_LOG="$case_log" \
  "$repo_dir/packages/management-api/bin/nix-me-api" local-ai >"$temp_dir/refresh.json"
jq -e '.localAI.health == "degraded"' "$temp_dir/refresh.json" >/dev/null
[[ ! -e "$case_log" ]] || fail "read-only refresh invoked the downloader"

echo "local AI model lifecycle contract passed"
