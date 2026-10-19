#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nix-me-private-state-test.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

cat >"$TEMP_DIR/desired-manifest.json" <<'JSON'
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
printf '{"applications":[]}\n' >"$TEMP_DIR/application-catalog.json"

cat >"$TEMP_DIR/fake-private-state-engine" <<'SH'
#!/bin/bash
case "${1:-} ${2:-}" in
  "--version ")
    echo "nix-me-apps 0.1.0"
    ;;
  "registry list")
    cat <<'JSON'
{"version":1,"applications":[{"id":"codex-cli","name":"Codex CLI","bundleId":"com.openai.codex.cli","installed":true,"capturable":false,"captureKinds":[],"exportableSettings":[],"managedPaths":[],"manualSteps":["Authenticate Codex CLI"]},{"id":"onepassword-cli","name":"1Password CLI","bundleId":"com.1password.cli","installed":true,"capturable":false,"captureKinds":[],"exportableSettings":[],"managedPaths":[],"manualSteps":["Authenticate 1Password CLI"]}]}
JSON
    ;;
  "diff --json")
    case " $* " in
      *" --only codex-cli "*)
        printf '%s\n' 'private@example.test token-secret' >&2
        cat <<'JSON'
{"apps":[{"id":"codex-cli"}],"checklist":[{"app":"codex-cli","step":"account-output","confirm":"full_manual","satisfied":false}],"summary":{"manual":1},"commandOutput":"private@example.test token-secret"}
JSON
        exit 3
        ;;
      *" --only onepassword-cli "*)
        printf '%s\n' 'vault@example.test session-secret' >&2
        cat <<'JSON'
{"apps":[{"id":"onepassword-cli"}],"checklist":[{"app":"onepassword-cli","step":"account-output","confirm":"full_manual","satisfied":true}],"summary":{"manual":0},"commandOutput":"vault@example.test session-secret"}
JSON
        ;;
      *)
        exit 98
        ;;
    esac
    ;;
  *)
    exit 98
    ;;
esac
SH
chmod +x "$TEMP_DIR/fake-private-state-engine"

export NIX_ME_CONFIG_DIR="$REPO_DIR"
export NIX_ME_SKIP_UPDATES=1
export NIX_ME_DESIRED_MANIFEST="$TEMP_DIR/desired-manifest.json"
export NIX_ME_APPLICATION_CATALOG="$TEMP_DIR/application-catalog.json"
export NIX_ME_APP_STATE_STATUS="$FIXTURES_DIR/app-state-status-v1.json"
export NIX_ME_APP_STATE_REGISTRY="$FIXTURES_DIR/app-state-registry-v1.json"
export NIX_ME_APP_STATE_PLAN="$FIXTURES_DIR/app-state-plan-v1.json"
export NIX_ME_LOCAL_AI_STATUS="$FIXTURES_DIR/local-ai-status-healthy-v1.json"
export NIX_ME_PRIVATE_STATE_TIMEOUT_SECONDS=1
export NIX_ME_APP_STATE_ENGINE="$TEMP_DIR/fake-private-state-engine"

"$REPO_DIR/packages/management-api/bin/nix-me-api" snapshot >"$TEMP_DIR/snapshot.json"

jq -e '
  any(.appStateSettings.applications[];
    .id == "onepassword-cli" and
    .privateState == {
      readiness: "ready",
      exclusionReason: "Account identity, email addresses, vaults, credentials, session tokens, and device trust remain on this Mac and are never exported."
    }) and
  any(.appStateSettings.applications[];
    .id == "codex-cli" and
    .privateState == {
      readiness: "notReady",
      exclusionReason: "OAuth and API credentials, account identity, sessions, and conversation data remain on this Mac and are never exported."
    }) and
  all(.appStateSettings.applications[] | select(.privateState != null);
    (.privateState | keys | sort) == ["exclusionReason", "readiness"])
' "$TEMP_DIR/snapshot.json" >/dev/null

if grep -Eq 'private@example|vault@example|token-secret|session-secret|account-output' \
  "$TEMP_DIR/snapshot.json"; then
  echo "private readiness details leaked into the management snapshot" >&2
  exit 1
fi

NIX_ME_APP_STATE_ENGINE="$TEMP_DIR/missing-engine" \
  "$REPO_DIR/packages/management-api/bin/nix-me-api" app-state-settings \
  >"$TEMP_DIR/unknown.json"
jq -e '
  all(.appStateSettings.applications[] | select(.id == "onepassword-cli" or .id == "codex-cli");
    .privateState.readiness == "unknown")
' "$TEMP_DIR/unknown.json" >/dev/null

jq -e '
  ."$defs".appStateSettings.properties.applications.items.properties.privateState == {
    type: ["object", "null"],
    required: ["readiness", "exclusionReason"],
    properties: {
      readiness: {enum: ["ready", "notReady", "unknown"]},
      exclusionReason: {type: "string", minLength: 1}
    },
    additionalProperties: true
  } and
  (."$defs".appStateSettings.properties.applications.items.required | index("privateState")) == null
' "$REPO_DIR/packages/management-api/schema/snapshot-v1.schema.json" >/dev/null

echo "private app-state API contract passed"
