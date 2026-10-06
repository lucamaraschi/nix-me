#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nix-me-api-test.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

export NIX_ME_CONFIG_DIR="$REPO_DIR"
export NIX_ME_SKIP_UPDATES=1
export NIX_ME_DESIRED_MANIFEST="$TEMP_DIR/desired-manifest.json"
FIXTURES_DIR="$REPO_DIR/packages/management-api/test/fixtures"
export NIX_ME_APP_STATE_ENGINE_VERSION="0.1.0"
export NIX_ME_APP_STATE_STATUS="$FIXTURES_DIR/app-state-status-v1.json"
export NIX_ME_LOCAL_AI_STATUS="$FIXTURES_DIR/local-ai-status-healthy-v1.json"

cat >"$NIX_ME_DESIRED_MANIFEST" <<'JSON'
{
  "schemaVersion": 1,
  "host": {
    "hostname": "contract-test",
    "machineName": "Contract Test",
    "machineType": "test",
    "username": "tester"
  },
  "software": {
    "nixPackages": [],
    "nixPackageDetails": [],
    "homebrew": {"formulae": [], "casks": [], "masApps": {}}
  },
  "projects": [],
  "source": {"contentHash": "fixture", "lockHash": "fixture"}
}
JSON

"$REPO_DIR/apps/cli/bin/nix-me" api snapshot >"$TEMP_DIR/snapshot.json"

schema_version="$(jq -r '.properties.schemaVersion.const' \
  "$REPO_DIR/packages/management-api/schema/snapshot-v1.schema.json")"
jq -e --argjson version "$schema_version" '.schemaVersion == $version' \
  "$TEMP_DIR/snapshot.json" >/dev/null

jq -e '
  .schemaVersion == 1 and
  (.generatedAt | type == "string") and
  (.host.hostname | type == "string") and
  (.configuration.applyState | IN("current", "pending", "unknown")) and
  ((.configuration.desiredSource | type) == "object") and
  (.inventory.desired.nixPackages | type == "array") and
  (.inventory.desired.nixPackageDetails | type == "array") and
  (.inventory.desired.homebrew.casks | type == "array") and
  (.updates.homebrew | type == "array") and
  (.updates.macAppStore | type == "array") and
  (.updates.nixFlake | type == "array") and
  (.projects | type == "array") and
  .appState.schemaVersion == 1 and
  .appState.engine == {available: true, version: "0.1.0"} and
  .appState.configuredRecipeCount == 2 and
  .appState.driftCount == 2 and
  .appState.manualResidueCount == 1 and
  .appState.lastApply == {
    status: "succeeded",
    time: "2026-10-05T17:56:00Z",
    message: "Applied 2 configured recipes"
  } and
  .appState.verification == {
    verifiedRecipeCount: 1,
    unverifiedRecipeCount: 1
  } and
  .appState.warnings == [] and
  .localAI.schemaVersion == 1 and
  .localAI.health == "healthy" and
  .localAI.ds4Checkout.state == "ready" and
  .localAI.piDs4Checkout.state == "ready" and
  .localAI.extension.state == "linked" and
  .localAI.runtime.state == "built" and
  .localAI.model.state == "present" and
  .localAI.server.state == "stopped" and
  .localAI.configuration == {state: "current", driftCount: 0} and
  .localAI.remediation == [] and
  (.warnings | type == "array")
' "$TEMP_DIR/snapshot.json" >/dev/null

for endpoint in status inventory updates projects app-state local-ai manifest; do
  "$REPO_DIR/apps/cli/bin/nix-me" api "$endpoint" >"$TEMP_DIR/$endpoint.json"
  jq -e '.schemaVersion == 1' "$TEMP_DIR/$endpoint.json" >/dev/null
done

jq -e --slurpfile snapshot "$TEMP_DIR/snapshot.json" '
  .appState == $snapshot[0].appState and
  .warnings == ($snapshot[0].warnings + $snapshot[0].appState.warnings)
' "$TEMP_DIR/app-state.json" >/dev/null

jq -e --slurpfile snapshot "$TEMP_DIR/snapshot.json" '
  .localAI == $snapshot[0].localAI and
  .warnings == $snapshot[0].warnings
' "$TEMP_DIR/local-ai.json" >/dev/null

jq -e '
  .properties.appState."$ref" == "#/$defs/appState" and
  ."$defs".appState.required == [
    "schemaVersion",
    "engine",
    "configuredRecipeCount",
    "driftCount",
    "manualResidueCount",
    "lastApply",
    "verification",
    "warnings"
  ] and
  ."$defs".appState.properties.lastApply.properties.status.enum == [
    "succeeded",
    "partial",
    "declined",
    "failed",
    null
  ] and
  ."$defs".appState.additionalProperties == true and
  .properties.localAI."$ref" == "#/$defs/localAI" and
  ."$defs".localAI.required == [
    "schemaVersion",
    "health",
    "summary",
    "ds4Checkout",
    "piDs4Checkout",
    "extension",
    "runtime",
    "model",
    "server",
    "configuration",
    "remediation"
  ] and
  ."$defs".localAI.properties.health.enum == ["healthy", "degraded", "unavailable"] and
  ."$defs".localAI.properties.server.properties.state.enum == ["running", "stopped", "unavailable"] and
  ."$defs".localAI.additionalProperties == true
' "$REPO_DIR/packages/management-api/schema/snapshot-v1.schema.json" >/dev/null

cat >"$TEMP_DIR/fake-local-ai-doctor" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$FAKE_LOCAL_AI_LOG"
cat "$FAKE_LOCAL_AI_STATUS"
SH
chmod +x "$TEMP_DIR/fake-local-ai-doctor"

(
  unset NIX_ME_LOCAL_AI_STATUS
  export NIX_ME_LOCAL_AI_DOCTOR="$TEMP_DIR/fake-local-ai-doctor"
  export FAKE_LOCAL_AI_LOG="$TEMP_DIR/fake-local-ai.log"
  export FAKE_LOCAL_AI_STATUS="$FIXTURES_DIR/local-ai-status-degraded-v1.json"
  "$REPO_DIR/apps/cli/bin/nix-me" api local-ai >"$TEMP_DIR/local-ai-live.json"
)
jq -e '
  .localAI.health == "degraded" and
  .localAI.piDs4Checkout.state == "missing" and
  .localAI.runtime.state == "notBuilt" and
  .localAI.model.state == "missing" and
  .localAI.configuration == {state: "drifted", driftCount: 2} and
  (.localAI.remediation | length) == 5
' "$TEMP_DIR/local-ai-live.json" >/dev/null
grep -qx -- '--json' "$TEMP_DIR/fake-local-ai.log"

NIX_ME_LOCAL_AI_STATUS="$FIXTURES_DIR/local-ai-status-unavailable-v1.json" \
  "$REPO_DIR/apps/cli/bin/nix-me" api local-ai >"$TEMP_DIR/local-ai-unavailable.json"
jq -e '
  .localAI.health == "unavailable" and
  .localAI.ds4Checkout.state == "unavailable" and
  .localAI.server.state == "unavailable" and
  .localAI.configuration == {state: "unavailable", driftCount: null}
' "$TEMP_DIR/local-ai-unavailable.json" >/dev/null

NIX_ME_LOCAL_AI_STATUS="$FIXTURES_DIR/local-ai-status-malformed.json" \
  "$REPO_DIR/apps/cli/bin/nix-me" api local-ai >"$TEMP_DIR/local-ai-malformed.json"
jq -e '
  .localAI.health == "unavailable" and
  .localAI.model.state == "unavailable" and
  .localAI.configuration.driftCount == null and
  (.warnings | any(. == "The local-AI status fixture is malformed or unreadable"))
' "$TEMP_DIR/local-ai-malformed.json" >/dev/null

(
  unset NIX_ME_LOCAL_AI_STATUS
  export NIX_ME_LOCAL_AI_DOCTOR=""
  "$REPO_DIR/apps/cli/bin/nix-me" api local-ai >"$TEMP_DIR/local-ai-tool-unavailable.json"
)
jq -e '
  .localAI.health == "unavailable" and
  (.warnings | any(. == "The local-AI status tool is unavailable"))
' "$TEMP_DIR/local-ai-tool-unavailable.json" >/dev/null

cat >"$TEMP_DIR/slow-local-ai-doctor" <<'SH'
#!/bin/bash
sleep 5
SH
chmod +x "$TEMP_DIR/slow-local-ai-doctor"
(
  unset NIX_ME_LOCAL_AI_STATUS
  export NIX_ME_LOCAL_AI_DOCTOR="$TEMP_DIR/slow-local-ai-doctor"
  export NIX_ME_LOCAL_AI_TIMEOUT_SECONDS=1
  "$REPO_DIR/apps/cli/bin/nix-me" api local-ai >"$TEMP_DIR/local-ai-timeout.json"
)
jq -e '
  .localAI.health == "unavailable" and
  (.warnings | any(. == "The local-AI status check timed out"))
' "$TEMP_DIR/local-ai-timeout.json" >/dev/null

cat >"$TEMP_DIR/fake-nix-me-apps" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$FAKE_APP_STATE_ENGINE_LOG"
case "${1:-}" in
  --version)
    echo "nix-me-apps 9.8.7"
    ;;
  status)
    jq --arg version "9.8.7" '.engine.version = $version' "$FAKE_APP_STATE_STATUS"
    ;;
  *)
    exit 98
    ;;
esac
SH
chmod +x "$TEMP_DIR/fake-nix-me-apps"

(
  unset NIX_ME_APP_STATE_ENGINE_VERSION
  unset NIX_ME_APP_STATE_STATUS
  export NIX_ME_APP_STATE_ENGINE="$TEMP_DIR/fake-nix-me-apps"
  export FAKE_APP_STATE_ENGINE_LOG="$TEMP_DIR/fake-engine.log"
  export FAKE_APP_STATE_STATUS="$FIXTURES_DIR/app-state-status-v1.json"
  "$REPO_DIR/apps/cli/bin/nix-me" api app-state >"$TEMP_DIR/app-state-live.json"
)

jq -e '
  .appState.engine == {available: true, version: "9.8.7"} and
  .appState.configuredRecipeCount == 2 and
  .appState.driftCount == 2 and
  .appState.manualResidueCount == 1
' "$TEMP_DIR/app-state-live.json" >/dev/null
available_recipe_count="$(find "$REPO_DIR/packages/app-state/recipes" -maxdepth 1 -type f \( -name '*.yaml' -o -name '*.yml' \) | wc -l | tr -d ' ')"
[[ "$available_recipe_count" -gt 2 ]]
grep -q '^status --json --recipe .* --values ' "$TEMP_DIR/fake-engine.log"
if grep -Eq '(^| )(apply|diff|registry)( |$)' "$TEMP_DIR/fake-engine.log"; then
  echo "app-state endpoint bypassed the engine status command" >&2
  exit 1
fi

(
  unset NIX_ME_APP_STATE_ENGINE_VERSION
  unset NIX_ME_APP_STATE_STATUS
  export NIX_ME_APP_STATE_ENGINE="$TEMP_DIR/missing-nix-me-apps"
  export NIX_ME_APP_STATE_STATE="$TEMP_DIR/missing-apps.json"
  "$REPO_DIR/apps/cli/bin/nix-me" api app-state >"$TEMP_DIR/app-state-unavailable.json"
)

jq -e '
  .appState.engine == {available: false, version: null} and
  .appState.configuredRecipeCount == null and
  .appState.driftCount == null and
  .appState.manualResidueCount == null and
  .appState.lastApply == {status: null, time: null, message: null} and
  .appState.verification == {
    verifiedRecipeCount: null,
    unverifiedRecipeCount: null
  } and
  (.appState.warnings | any(. == "The app-state engine is unavailable")) and
  (.appState.warnings | any(. == "The persisted app-state status is unavailable"))
' "$TEMP_DIR/app-state-unavailable.json" >/dev/null

(
  export NIX_ME_APP_STATE_STATUS="$FIXTURES_DIR/app-state-malformed.json"
  "$REPO_DIR/apps/cli/bin/nix-me" api app-state >"$TEMP_DIR/app-state-malformed.json"
)

jq -e '
  .appState.configuredRecipeCount == null and
  .appState.driftCount == null and
  .appState.manualResidueCount == null and
  .appState.lastApply == {status: null, time: null, message: null} and
  (.appState.warnings | any(. == "The app-state status fixture is malformed or unreadable"))
' "$TEMP_DIR/app-state-malformed.json" >/dev/null

for apply_status in succeeded partial declined failed; do
  jq --arg status "$apply_status" \
    '.lastApply = {status: $status, time: "2026-10-05T18:00:00Z", message: null}' \
    "$FIXTURES_DIR/app-state-status-v1.json" >"$TEMP_DIR/status-$apply_status-fixture.json"
  NIX_ME_APP_STATE_STATUS="$TEMP_DIR/status-$apply_status-fixture.json" \
    "$REPO_DIR/apps/cli/bin/nix-me" api app-state >"$TEMP_DIR/status-$apply_status.json"
  jq -e --arg status "$apply_status" '.appState.lastApply.status == $status' \
    "$TEMP_DIR/status-$apply_status.json" >/dev/null
done

(
  unset NIX_ME_APP_STATE_STATUS
  export NIX_ME_APP_STATE_REGISTRY="$FIXTURES_DIR/app-state-registry-v1.json"
  export NIX_ME_APP_STATE_PLAN="$FIXTURES_DIR/app-state-plan-v1.json"
  export NIX_ME_APP_STATE_STATE="$FIXTURES_DIR/app-state-state-v1.json"
  export NIX_ME_APP_STATE_LAST_APPLY="$FIXTURES_DIR/app-state-last-apply-v1.json"
  "$REPO_DIR/apps/cli/bin/nix-me" api app-state >"$TEMP_DIR/app-state-legacy-fixtures.json"
)
jq -e '
  .appState.configuredRecipeCount == null and
  .appState.verification == {
    verifiedRecipeCount: null,
    unverifiedRecipeCount: null
  } and
  .appState.lastApply.status == "succeeded" and
  (.appState.warnings | any(. == "Configured app-state recipes are unknown without engine status"))
' "$TEMP_DIR/app-state-legacy-fixtures.json" >/dev/null

if "$REPO_DIR/apps/cli/bin/nix-me" api not-an-endpoint >"$TEMP_DIR/unknown.json"; then
  echo "unknown API endpoint unexpectedly succeeded" >&2
  exit 1
else
  unknown_status=$?
fi
[[ "$unknown_status" == 64 ]]
jq -e '
  .schemaVersion == 1 and
  .error.code == "unknown_endpoint" and
  (.error.message | type == "string")
' "$TEMP_DIR/unknown.json" >/dev/null

echo "nix-me API contract passed"
