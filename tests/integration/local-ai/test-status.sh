#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
doctor="$repo_dir/tools/local-ai/doctor.sh"
fixtures="$repo_dir/tests/integration/local-ai/fixtures"
temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/nix-me-local-ai-status.XXXXXX")"
trap 'rm -rf "$temp_dir"' EXIT

run_status() {
  local fixture="$1"
  LOCAL_AI_STATUS_PROBE="$fixture" \
    DS4_RUNTIME_DIR="/Users/tester/src/ai/ds4" \
    PI_DS4_DIR="/Users/tester/src/ai/pi-ds4" \
    PI_CODING_AGENT_DIR="/Users/tester/.pi/agent" \
    LOCAL_AI_MODEL_PATH="/Users/tester/src/ai/ds4/ds4flash.gguf" \
    bash "$doctor" --json
}

run_status "$fixtures/probe-healthy.json" >"$temp_dir/healthy.json"
run_status "$fixtures/probe-healthy.json" >"$temp_dir/healthy-repeat.json"
cmp "$temp_dir/healthy.json" "$temp_dir/healthy-repeat.json"
jq -e '
  .schemaVersion == 1 and
  .health == "healthy" and
  .server.state == "stopped" and
  .configuration == {state: "current", driftCount: 0} and
  .remediation == []
' "$temp_dir/healthy.json" >/dev/null

run_status "$fixtures/probe-degraded.json" >"$temp_dir/degraded.json"
jq -e '
  .health == "degraded" and
  .piDs4Checkout.state == "missing" and
  .runtime.state == "notBuilt" and
  .model.state == "missing" and
  .configuration == {state: "drifted", driftCount: 2} and
  (.remediation | length) == 5
' "$temp_dir/degraded.json" >/dev/null

run_status "$fixtures/probe-unavailable.json" >"$temp_dir/unavailable.json"
jq -e '
  .health == "unavailable" and
  .ds4Checkout.state == "unavailable" and
  .server.state == "unavailable" and
  .configuration == {state: "unavailable", driftCount: null} and
  (.remediation | length) == 1
' "$temp_dir/unavailable.json" >/dev/null

run_status "$fixtures/probe-malformed.json" >"$temp_dir/malformed.json"
jq -e '
  .health == "unavailable" and
  .model.state == "unavailable" and
  .configuration.driftCount == null and
  (.remediation | any(test("malformed")))
' "$temp_dir/malformed.json" >/dev/null

home="$temp_dir/home"
ds4="$home/src/ai/ds4"
pi_ds4="$home/src/ai/pi-ds4"
agent="$home/.pi/agent"
mkdir -p "$ds4" "$pi_ds4" "$agent/extensions" "$home/.pi/ds4"
touch "$ds4/Makefile" "$ds4/download_model.sh" "$ds4/ds4flash.gguf"
touch "$pi_ds4/install-pi-extension-local.sh"
printf '#!/bin/sh\n' >"$ds4/ds4-server"
chmod +x "$ds4/ds4-server"
ln -s "$pi_ds4" "$agent/extensions/pi-ds4"
ln -s "$ds4" "$home/.pi/ds4/support"
cat >"$agent/settings.json" <<'JSON'
{"defaultProvider":"ds4","defaultModel":"dsv4-flash-q2"}
JSON
cat >"$home/.pi/ds4/settings.json" <<JSON
{
  "\$schema": "https://raw.githubusercontent.com/mitsuhiko/pi-ds4/main/settings.schema.json",
  "protocol": "openai-responses",
  "runtimeDir": "$ds4",
  "autoUpdate": false,
  "contextTokens": 32768,
  "power": 70,
  "readyTimeoutMs": 900000
}
JSON

before_probe="$(find "$home" -type f -exec shasum {} \; | sort)"
HOME="$home" \
  DS4_RUNTIME_DIR="$ds4" \
  PI_DS4_DIR="$pi_ds4" \
  PI_CODING_AGENT_DIR="$agent" \
  LOCAL_AI_MODEL_PATH="$ds4/ds4flash.gguf" \
  LOCAL_AI_SERVER_STATE_OVERRIDE=stopped \
  bash "$doctor" --json >"$temp_dir/filesystem.json"
after_probe="$(find "$home" -type f -exec shasum {} \; | sort)"
[[ "$before_probe" == "$after_probe" ]]
jq -e '
  .health == "healthy" and
  .ds4Checkout.state == "ready" and
  .piDs4Checkout.state == "ready" and
  .extension.state == "linked" and
  .runtime.state == "built" and
  .model.state == "present" and
  .server.state == "stopped" and
  .configuration == {state: "current", driftCount: 0}
' "$temp_dir/filesystem.json" >/dev/null

echo "local AI JSON status contract passed"
