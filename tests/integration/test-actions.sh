#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nix-me-action-test.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

export NIX_ME_CONFIG_DIR="$REPO_DIR"
export NIX_ME_ACTION_DRY_RUN=1

grep -Fq 'NIX_ME_USER_BUILD_APPLY=1' "$REPO_DIR/packages/management-api/bin/nix-me-action"
grep -Fq 'build --json --no-link --impure "$flake_ref"' "$REPO_DIR/packages/management-api/bin/nix-me-action"
grep -Fq 'flake_ref="path:$CONFIG_DIR#darwinConfigurations.$host_name.system"' "$REPO_DIR/packages/management-api/bin/nix-me-action"
grep -Fq 'NIX_ME_SOURCE_REVISION=' "$REPO_DIR/packages/management-api/bin/nix-me-action"
grep -Fq '" -p /nix/var/nix/profiles/system --set "' "$REPO_DIR/packages/management-api/bin/nix-me-action"
grep -Fq 'quoted form of rebuildPath & " activate"' "$REPO_DIR/packages/management-api/bin/nix-me-action"
grep -Fq 'GIT_CONFIG_KEY_0=safe.directory' "$REPO_DIR/Makefile"
grep -Fq 'GIT_CONFIG_VALUE_0="$(FLAKE_DIR)"' "$REPO_DIR/Makefile"

"$REPO_DIR/apps/cli/bin/nix-me" action update >"$TEMP_DIR/result.json" <<'JSON'
{"items":[{"name":"nixpkgs","kind":"nixFlake","installedVersions":["old"],"availableVersion":"new"},{"name":"coreutils","kind":"formula","installedVersions":["1"],"availableVersion":"2"},{"name":"raycast","kind":"cask","installedVersions":["1"],"availableVersion":"2"},{"name":"PDF Expert","kind":"mas","installedVersions":["1"],"availableVersion":"2","storeId":1055273043}]}
JSON

jq -e '
  .schemaVersion == 1 and
  .success and
  .requiresApply and
  (.results | length == 4) and
  all(.results[]; .success)
' "$TEMP_DIR/result.json" >/dev/null

if "$REPO_DIR/apps/cli/bin/nix-me" action update >"$TEMP_DIR/invalid.json" <<'JSON'
{"items":[{"name":"unsafe; command","kind":"formula","installedVersions":[],"availableVersion":"2"}]}
JSON
then
  echo "Invalid update request was accepted" >&2
  exit 1
fi

jq -e '.error.code == "invalid_request"' "$TEMP_DIR/invalid.json" >/dev/null

NIX_ME_HOSTNAME=test-host NIX_ME_USERNAME=test-user \
  "$REPO_DIR/apps/cli/bin/nix-me" action apply >"$TEMP_DIR/apply.json" 2>"$TEMP_DIR/apply-progress.log"
jq -e '
  .schemaVersion == 1 and
  .action == "apply" and
  .success and
  (.message | contains("Would apply configuration for test-host as test-user"))
' "$TEMP_DIR/apply.json" >/dev/null
grep -Fq $'NIX_ME_PROGRESS\tpreparing\t' "$TEMP_DIR/apply-progress.log"

APPLY_REPO="$TEMP_DIR/apply-repo"
APPLY_SYSTEM="$TEMP_DIR/built-system"
mkdir -p "$APPLY_REPO" "$APPLY_SYSTEM/sw/bin"
printf '{}\n' >"$APPLY_REPO/flake.nix"
printf '#!/bin/bash\n' >"$APPLY_SYSTEM/sw/bin/darwin-rebuild"
chmod +x "$APPLY_SYSTEM/sw/bin/darwin-rebuild"

cat >"$TEMP_DIR/fake-nix" <<'SH'
#!/bin/bash
[[ " $* " == *" build --json --no-link --impure "* ]] || exit 64
[[ "$*" == *"path:$NIX_ME_TEST_CONFIG#darwinConfigurations.test-host.system"* ]] || exit 65
[[ "$HOSTNAME" == "test-host" ]] || exit 66
[[ "$USERNAME" == "test-user" ]] || exit 67
[[ "$MACHINE_NAME" == "Test Mac" ]] || exit 68
[[ "$MACHINE_TYPE" == "test" ]] || exit 69
[[ "$NIX_ME_SOURCE_REVISION" == "abc123" ]] || exit 70
jq -n --arg out "$NIX_ME_TEST_SYSTEM" '[{outputs:{out:$out}}]'
SH
cat >"$TEMP_DIR/fake-nix-env" <<'SH'
#!/bin/bash
exit 1
SH
cat >"$TEMP_DIR/fake-osascript" <<'SH'
#!/bin/bash
[[ "$*" == *'" -p /nix/var/nix/profiles/system --set "'* ]] || exit 71
[[ "$*" == *'set rebuildPath to systemPath & "/sw/bin/darwin-rebuild"'* ]] || exit 72
[[ " $* " == *" -- $NIX_ME_TEST_SYSTEM test-user $NIX_ME_NIX_ENV_BIN "* ]] || exit 73
printf '%s\n' 'Configuration activated'
SH
chmod +x "$TEMP_DIR/fake-nix" "$TEMP_DIR/fake-nix-env" "$TEMP_DIR/fake-osascript"

NIX_ME_CONFIG_DIR="$APPLY_REPO" \
  NIX_ME_ACTION_DRY_RUN=0 \
  NIX_ME_HOSTNAME=test-host \
  NIX_ME_USERNAME=test-user \
  NIX_ME_MACHINE_NAME='Test Mac' \
  NIX_ME_MACHINE_TYPE=test \
  NIX_ME_SOURCE_REVISION=abc123 \
  NIX_ME_NIX_BIN="$TEMP_DIR/fake-nix" \
  NIX_ME_NIX_ENV_BIN="$TEMP_DIR/fake-nix-env" \
  NIX_ME_ADMINISTRATOR_RUNNER="$TEMP_DIR/fake-osascript" \
  NIX_ME_TEST_CONFIG="$APPLY_REPO" \
  NIX_ME_TEST_SYSTEM="$APPLY_SYSTEM" \
  "$REPO_DIR/packages/management-api/bin/nix-me-action" apply \
    >"$TEMP_DIR/apply-real.json" 2>"$TEMP_DIR/apply-real-progress.log"
jq -e '
  .schemaVersion == 1 and
  .action == "apply" and
  .success and
  .message == "Configuration activated"
' "$TEMP_DIR/apply-real.json" >/dev/null
grep -Fq $'NIX_ME_PROGRESS\tpreparing\t' "$TEMP_DIR/apply-real-progress.log"
grep -Fq $'NIX_ME_PROGRESS\tbuilding\t' "$TEMP_DIR/apply-real-progress.log"
grep -Fq $'NIX_ME_PROGRESS\tactivating\t' "$TEMP_DIR/apply-real-progress.log"

NIX_ME_HOSTNAME=test-host \
  "$REPO_DIR/apps/cli/bin/nix-me" action sync-projects >"$TEMP_DIR/projects.json"
jq -e '
  .schemaVersion == 1 and
  .action == "sync-projects" and
  .success and
  (.message | contains("Would sync projects for test-host"))
' "$TEMP_DIR/projects.json" >/dev/null

PROJECT_REPO="$TEMP_DIR/project-repo"
mkdir -p "$PROJECT_REPO/config/projects/profiles" "$PROJECT_REPO/config/projects/machines"
printf '{}\n' >"$PROJECT_REPO/config/projects/shared.json"
git -C "$PROJECT_REPO" init -q
git -C "$PROJECT_REPO" add config/projects/shared.json

project_request='{"name":"example","url":"https://github.com/example/example.git","path":"src/example/example","branch":null,"remote":"origin","clone":true,"update":true,"scope":"machine","profile":null}'
printf '%s\n' "$project_request" | \
  NIX_ME_CONFIG_DIR="$PROJECT_REPO" \
  NIX_ME_HOSTNAME=test-host \
  "$REPO_DIR/apps/cli/bin/nix-me" action project-preview >"$TEMP_DIR/project-preview.json"
jq -e '
  .schemaVersion == 1 and
  .action == "project-preview" and
  .success and .changed and (.written | not) and (.replaced | not) and
  .destination == "config/projects/machines/test-host.json" and
  .project.path == "src/example/example"
' "$TEMP_DIR/project-preview.json" >/dev/null
test ! -e "$PROJECT_REPO/config/projects/machines/test-host.json"

printf '%s\n' "$project_request" | \
  NIX_ME_CONFIG_DIR="$PROJECT_REPO" \
  NIX_ME_HOSTNAME=test-host \
  "$REPO_DIR/apps/cli/bin/nix-me" action project-save >"$TEMP_DIR/project-save.json"
jq -e '
  .success and .action == "project-save" and .changed and .written and .requiresSync and
  .destination == "config/projects/machines/test-host.json"
' "$TEMP_DIR/project-save.json" >/dev/null
jq -e '.example == {
  url: "https://github.com/example/example.git",
  path: "src/example/example",
  branch: null,
  remote: "origin",
  clone: true,
  update: true
}' "$PROJECT_REPO/config/projects/machines/test-host.json" >/dev/null

if printf '%s\n' '{"name":"unsafe","url":"https://github.com/example/unsafe.git","path":"../outside","branch":null,"remote":"origin","clone":true,"update":true,"scope":"shared","profile":null}' | \
  NIX_ME_CONFIG_DIR="$PROJECT_REPO" \
  NIX_ME_HOSTNAME=test-host \
  "$REPO_DIR/apps/cli/bin/nix-me" action project-save >"$TEMP_DIR/project-invalid.json"; then
  echo "Invalid project path was accepted" >&2
  exit 1
fi
jq -e '.error.code == "invalid_request"' "$TEMP_DIR/project-invalid.json" >/dev/null

if printf '%s\n' '{"name":"duplicate","url":"git@github.com:example/duplicate.git","path":"src/example/example","branch":"main","remote":"origin","clone":true,"update":true,"scope":"shared","profile":null}' | \
  NIX_ME_CONFIG_DIR="$PROJECT_REPO" \
  NIX_ME_HOSTNAME=test-host \
  "$REPO_DIR/apps/cli/bin/nix-me" action project-save >"$TEMP_DIR/project-duplicate.json"; then
  echo "Duplicate project path was accepted" >&2
  exit 1
fi
jq -e '.error.code == "duplicate_project_path"' "$TEMP_DIR/project-duplicate.json" >/dev/null

SETTINGS_REPO="$TEMP_DIR/settings-repo"
mkdir -p \
  "$SETTINGS_REPO/packages/app-state/recipes" \
  "$SETTINGS_REPO/config/app-state/shared" \
  "$SETTINGS_REPO/config/app-state/machines/test-host"
printf '{}\n' >"$SETTINGS_REPO/config/app-state/shared/settings.json"
printf 'false\n' >"$SETTINGS_REPO/config/app-state/machines/test-host/enabled"
git -C "$SETTINGS_REPO" init -q
git -C "$SETTINGS_REPO" add config/app-state/shared/settings.json \
  config/app-state/machines/test-host/enabled
cat >"$TEMP_DIR/fake-nix-me-apps" <<'SH'
#!/bin/bash
if [[ "${1:-}" != "snapshot" ]]; then
  exit 64
fi
[[ -n "${NIX_ME_TEST_ENGINE_ARGS:-}" ]] && printf '%s\n' "$*" >"$NIX_ME_TEST_ENGINE_ARGS"
app_id=''
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--only" ]]; then
    app_id="${2:-}"
    shift 2
  else
    shift
  fi
done
if [[ "$app_id" == "hammerspoon" ]]; then
  jq -n --arg source 'hs.hotkey.bind({"cmd"}, "k", function() hs.alert.show("ready") end)\n' '
    {
      version: 1,
      values: {hammerspoon: {init_lua: $source}},
      applications: [{
        id: "hammerspoon",
        name: "Hammerspoon",
        bundleId: "org.hammerspoon.Hammerspoon",
        captured: [{kind:"file",bind:"init_lua",valueCount:1}],
        skipped: []
      }],
      redaction: {policy:"default_closed",count:0,items:[]}
    }
  '
else
  cat <<'JSON'
{
  "version": 1,
  "values": {"rectangle": {"gapSize": 12, "launchOnLogin": true}},
  "applications": [{
    "id": "rectangle",
    "name": "Rectangle",
    "bundleId": "com.knollsoft.Rectangle",
    "captured": [{"kind":"defaults","bind":"defaults","valueCount":2}],
    "skipped": []
  }],
  "redaction": {"policy":"default_closed","count":1,"items":[{"path":"rectangle.apiToken","reason":"sensitive_key","action":"removed"}]}
}
JSON
fi
SH
chmod +x "$TEMP_DIR/fake-nix-me-apps"

settings_request='{"appId":"rectangle","scope":"shared"}'
printf '%s\n' "$settings_request" | \
  NIX_ME_CONFIG_DIR="$SETTINGS_REPO" \
  NIX_ME_APP_STATE_ENGINE="$TEMP_DIR/fake-nix-me-apps" \
  NIX_ME_TEST_ENGINE_ARGS="$TEMP_DIR/engine-args" \
  NIX_ME_HOSTNAME=test-host \
  NIX_ME_ACTION_DRY_RUN=0 \
  "$REPO_DIR/apps/cli/bin/nix-me" action settings-preview >"$TEMP_DIR/settings-preview.json"
jq -e '
  .schemaVersion == 1 and
  .action == "settings-preview" and
  .success and
  .changed and
  .destination == "config/app-state/shared/settings.json" and
  .redaction.count == 1 and
  (.preview | fromjson | .gapSize == 12)
' "$TEMP_DIR/settings-preview.json" >/dev/null
jq -e 'length == 0' "$SETTINGS_REPO/config/app-state/shared/settings.json" >/dev/null
if grep -Fq -- '--confirm-reviewed-text' "$TEMP_DIR/engine-args"; then
  echo "Structured settings capture unexpectedly confirmed reviewed text" >&2
  exit 1
fi

printf '%s\n' '{"appId":"hammerspoon","scope":"machine","confirmReviewedText":true}' | \
  NIX_ME_CONFIG_DIR="$SETTINGS_REPO" \
  NIX_ME_APP_STATE_ENGINE="$TEMP_DIR/fake-nix-me-apps" \
  NIX_ME_TEST_ENGINE_ARGS="$TEMP_DIR/engine-args" \
  NIX_ME_HOSTNAME=test-host \
  NIX_ME_ACTION_DRY_RUN=0 \
  "$REPO_DIR/apps/cli/bin/nix-me" action settings-preview >"$TEMP_DIR/settings-reviewed-preview.json"
jq -e '
  .success and
  .destination == "config/app-state/machines/test-host/settings.json" and
  (.preview | fromjson | .init_lua | contains("hs.hotkey.bind"))
' "$TEMP_DIR/settings-reviewed-preview.json" >/dev/null
grep -Fq -- '--confirm-reviewed-text' "$TEMP_DIR/engine-args"

printf '%s\n' "$settings_request" | \
  NIX_ME_CONFIG_DIR="$SETTINGS_REPO" \
  NIX_ME_APP_STATE_ENGINE="$TEMP_DIR/fake-nix-me-apps" \
  NIX_ME_ACTION_DRY_RUN=0 \
  "$REPO_DIR/apps/cli/bin/nix-me" action settings-save >"$TEMP_DIR/settings-save.json"
jq -e '.success and .action == "settings-save" and .changed and .written' "$TEMP_DIR/settings-save.json" >/dev/null
jq -e '.rectangle == {gapSize: 12, launchOnLogin: true}' \
  "$SETTINGS_REPO/config/app-state/shared/settings.json" >/dev/null

if printf '%s\n' '{"appId":"rectangle","scope":"profile","profile":"../unsafe"}' | \
  NIX_ME_CONFIG_DIR="$SETTINGS_REPO" \
  NIX_ME_APP_STATE_ENGINE="$TEMP_DIR/fake-nix-me-apps" \
  "$REPO_DIR/apps/cli/bin/nix-me" action settings-save >"$TEMP_DIR/settings-invalid.json"; then
  echo "Invalid settings scope was accepted" >&2
  exit 1
fi
jq -e '.error.code == "invalid_request"' "$TEMP_DIR/settings-invalid.json" >/dev/null

if printf '%s\n' '{"appId":"hammerspoon","scope":"shared","confirmReviewedText":"yes"}' | \
  NIX_ME_CONFIG_DIR="$SETTINGS_REPO" \
  NIX_ME_APP_STATE_ENGINE="$TEMP_DIR/fake-nix-me-apps" \
  "$REPO_DIR/apps/cli/bin/nix-me" action settings-preview >"$TEMP_DIR/settings-confirm-invalid.json"; then
  echo "Non-boolean reviewed-text confirmation was accepted" >&2
  exit 1
fi
jq -e '.error.code == "invalid_request"' "$TEMP_DIR/settings-confirm-invalid.json" >/dev/null

NIX_ME_CONFIG_DIR="$SETTINGS_REPO" \
  NIX_ME_HOSTNAME=test-host \
  NIX_ME_ACTION_DRY_RUN=0 \
  "$REPO_DIR/apps/cli/bin/nix-me" action harness-enable >"$TEMP_DIR/harness-enable.json"
jq -e '
  .schemaVersion == 1 and
  .action == "harness-enable" and
  .success and .enabled and .changed and .written and .tracked and .requiresApply and
  .destination == "config/app-state/machines/test-host/enabled"
' "$TEMP_DIR/harness-enable.json" >/dev/null
jq -e '. == true' "$SETTINGS_REPO/config/app-state/machines/test-host/enabled" >/dev/null

NIX_ME_CONFIG_DIR="$SETTINGS_REPO" \
  NIX_ME_HOSTNAME=test-host \
  NIX_ME_ACTION_DRY_RUN=0 \
  "$REPO_DIR/apps/cli/bin/nix-me" action harness-enable >"$TEMP_DIR/harness-enabled.json"
jq -e '.success and .enabled and (.changed | not) and (.written | not) and (.requiresApply | not)' \
  "$TEMP_DIR/harness-enabled.json" >/dev/null

if NIX_ME_CONFIG_DIR="$SETTINGS_REPO" \
  NIX_ME_HOSTNAME='../unsafe' \
  "$REPO_DIR/apps/cli/bin/nix-me" action harness-enable >"$TEMP_DIR/harness-invalid.json"; then
  echo "Invalid harness hostname was accepted" >&2
  exit 1
fi
jq -e '.error.code == "invalid_configuration"' "$TEMP_DIR/harness-invalid.json" >/dev/null

echo "nix-me action contract passed"
