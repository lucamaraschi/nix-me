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
export NIX_ME_APP_STATE_REGISTRY="$FIXTURES_DIR/app-state-registry-v1.json"
export NIX_ME_APP_STATE_PLAN="$FIXTURES_DIR/app-state-plan-v1.json"
export NIX_ME_APP_STATE_STATE="$FIXTURES_DIR/app-state-state-v1.json"
export NIX_ME_APP_STATE_LAST_APPLY="$FIXTURES_DIR/app-state-last-apply-v1.json"

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
  .appState.configuredRecipeCount == 4 and
  .appState.driftCount == 2 and
  .appState.manualResidueCount == 1 and
  .appState.lastApply == {
    status: "succeeded",
    time: "2026-10-05T17:56:00Z",
    message: "Applied 4 configured recipes"
  } and
  .appState.verification == {
    verifiedRecipeCount: 1,
    unverifiedRecipeCount: 3
  } and
  .appState.warnings == [] and
  (.warnings | type == "array")
' "$TEMP_DIR/snapshot.json" >/dev/null

for endpoint in status inventory updates projects app-state manifest; do
  "$REPO_DIR/apps/cli/bin/nix-me" api "$endpoint" >"$TEMP_DIR/$endpoint.json"
  jq -e '.schemaVersion == 1' "$TEMP_DIR/$endpoint.json" >/dev/null
done

jq -e --slurpfile snapshot "$TEMP_DIR/snapshot.json" '
  .appState == $snapshot[0].appState and
  .warnings == ($snapshot[0].warnings + $snapshot[0].appState.warnings)
' "$TEMP_DIR/app-state.json" >/dev/null

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
    "failed",
    null
  ] and
  ."$defs".appState.additionalProperties == true
' "$REPO_DIR/packages/management-api/schema/snapshot-v1.schema.json" >/dev/null

cat >"$TEMP_DIR/fake-nix-me-apps" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$FAKE_APP_STATE_ENGINE_LOG"
case "${1:-}" in
  --version)
    echo "nix-me-apps 9.8.7"
    ;;
  registry)
    cat "$FAKE_APP_STATE_REGISTRY"
    ;;
  diff)
    case " $* " in
      *" --no-exec "*) ;;
      *) exit 99 ;;
    esac
    cat "$FAKE_APP_STATE_PLAN"
    exit 2
    ;;
  *)
    exit 98
    ;;
esac
SH
chmod +x "$TEMP_DIR/fake-nix-me-apps"

(
  unset NIX_ME_APP_STATE_ENGINE_VERSION
  unset NIX_ME_APP_STATE_REGISTRY
  unset NIX_ME_APP_STATE_PLAN
  export NIX_ME_APP_STATE_ENGINE="$TEMP_DIR/fake-nix-me-apps"
  export FAKE_APP_STATE_ENGINE_LOG="$TEMP_DIR/fake-engine.log"
  export FAKE_APP_STATE_REGISTRY="$FIXTURES_DIR/app-state-registry-v1.json"
  export FAKE_APP_STATE_PLAN="$FIXTURES_DIR/app-state-plan-v1.json"
  "$REPO_DIR/apps/cli/bin/nix-me" api app-state >"$TEMP_DIR/app-state-live.json"
)

jq -e '
  .appState.engine == {available: true, version: "9.8.7"} and
  .appState.configuredRecipeCount == 4 and
  .appState.driftCount == 2 and
  .appState.manualResidueCount == 1
' "$TEMP_DIR/app-state-live.json" >/dev/null
grep -q '^registry validate --json --recipe ' "$TEMP_DIR/fake-engine.log"
grep -q '^diff --json --no-exec --skip-missing --recipe ' "$TEMP_DIR/fake-engine.log"
if grep -Eq '(^| )apply( |$)' "$TEMP_DIR/fake-engine.log"; then
  echo "app-state endpoint attempted a mutation" >&2
  exit 1
fi

(
  unset NIX_ME_APP_STATE_ENGINE_VERSION
  unset NIX_ME_APP_STATE_REGISTRY
  unset NIX_ME_APP_STATE_PLAN
  unset NIX_ME_APP_STATE_LAST_APPLY
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
  export NIX_ME_APP_STATE_PLAN="$FIXTURES_DIR/app-state-malformed.json"
  export NIX_ME_APP_STATE_STATE="$FIXTURES_DIR/app-state-malformed.json"
  export NIX_ME_APP_STATE_LAST_APPLY="$FIXTURES_DIR/app-state-malformed.json"
  "$REPO_DIR/apps/cli/bin/nix-me" api app-state >"$TEMP_DIR/app-state-malformed.json"
)

jq -e '
  .appState.configuredRecipeCount == 4 and
  .appState.driftCount == null and
  .appState.manualResidueCount == null and
  .appState.lastApply == {status: null, time: null, message: null} and
  (.appState.warnings | any(. == "The app-state plan status is malformed or unreadable")) and
  (.appState.warnings | any(. == "The persisted app-state status is malformed")) and
  (.appState.warnings | any(. == "The last app-state apply status is malformed"))
' "$TEMP_DIR/app-state-malformed.json" >/dev/null

for apply_status in succeeded partial failed; do
  jq -n \
    --arg status "$apply_status" \
    '{status: $status, time: "2026-10-05T18:00:00Z", message: null}' \
    >"$TEMP_DIR/last-apply-$apply_status.json"
  NIX_ME_APP_STATE_LAST_APPLY="$TEMP_DIR/last-apply-$apply_status.json" \
    "$REPO_DIR/apps/cli/bin/nix-me" api app-state >"$TEMP_DIR/status-$apply_status.json"
  jq -e --arg status "$apply_status" '.appState.lastApply.status == $status' \
    "$TEMP_DIR/status-$apply_status.json" >/dev/null
done

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
