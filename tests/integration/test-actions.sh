#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nix-me-action-test.XXXXXX")"
pause_apply_pid=""
trap '[[ -n "$pause_apply_pid" ]] && kill "$pause_apply_pid" >/dev/null 2>&1 || true; rm -rf "$TEMP_DIR"' EXIT

export NIX_ME_CONFIG_DIR="$REPO_DIR"
export NIX_ME_ACTION_DRY_RUN=1

grep -Fq 'NIX_ME_USER_BUILD_APPLY=1' "$REPO_DIR/packages/management-api/bin/nix-me-action"
grep -Fq 'build --json --no-link --impure --log-format internal-json "$flake_ref"' "$REPO_DIR/packages/management-api/bin/nix-me-action"
grep -Fq 'flake_ref="path:$CONFIG_DIR#darwinConfigurations.$host_name.system"' "$REPO_DIR/packages/management-api/bin/nix-me-action"
grep -Fq 'NIX_ME_SOURCE_REVISION=' "$REPO_DIR/packages/management-api/bin/nix-me-action"
grep -Fq 'activation_runner="$system_path/etc/nix-me/activate-system"' "$REPO_DIR/packages/management-api/bin/nix-me-action"
grep -Fq 'quoted form of activationRunner & " " & quoted form of systemPath' "$REPO_DIR/packages/management-api/bin/nix-me-action"
grep -Fq 'trap cleanup EXIT' "$REPO_DIR/packages/management-api/bin/nix-me-activate-system"
grep -Fq "trap 'exit 130' INT TERM HUP" "$REPO_DIR/packages/management-api/bin/nix-me-activate-system"
grep -Fq '/usr/sbin/visudo -cf /etc/sudoers' "$REPO_DIR/packages/management-api/bin/nix-me-activate-system"
grep -Fq '/usr/bin/sudo -K' "$REPO_DIR/packages/management-api/bin/nix-me-activate-system"
grep -Fq 'install-mas-apps' "$REPO_DIR/packages/management-api/bin/nix-me-activate-system"
grep -Fq '/bin/launchctl asuser "$user_id"' "$REPO_DIR/packages/management-api/bin/nix-me-activate-system"
grep -Fq 'migrate_legacy_lock' "$REPO_DIR/packages/management-api/bin/nix-me-activate-system"
grep -Fq '/usr/bin/lockf -t "$lock_timeout_seconds" 9' "$REPO_DIR/packages/management-api/bin/nix-me-activate-system"
grep -Fq $'NIX_ME_PROGRESS\\tactivating\\tWaiting for another system activation' "$REPO_DIR/packages/management-api/bin/nix-me-activate-system"
grep -Fq 'exec 9>&-' "$REPO_DIR/packages/management-api/bin/nix-me-activate-system"
! grep -Fq 'another system activation is already running' "$REPO_DIR/packages/management-api/bin/nix-me-activate-system"
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
mkdir -p "$APPLY_REPO" "$APPLY_SYSTEM/sw/bin" "$APPLY_SYSTEM/etc/nix-me"
printf '{}\n' >"$APPLY_REPO/flake.nix"
printf '#!/bin/bash\n' >"$APPLY_SYSTEM/sw/bin/darwin-rebuild"
printf '#!/bin/bash\n' >"$APPLY_SYSTEM/etc/nix-me/activate-system"
cat >"$APPLY_SYSTEM/etc/nix-me/manifest.json" <<'JSON'
{"software":{"homebrew":{"formulae":["ripgrep"],"casks":["raycast"],"masApps":{"Xcode":497799835}}}}
JSON
chmod +x "$APPLY_SYSTEM/sw/bin/darwin-rebuild" "$APPLY_SYSTEM/etc/nix-me/activate-system"

cat >"$TEMP_DIR/fake-nix" <<'SH'
#!/bin/bash
[[ -z "${NIX_ME_TEST_NIX_MARKER:-}" ]] || touch "$NIX_ME_TEST_NIX_MARKER"
[[ " $* " == *" build --json --no-link --impure "* ]] || exit 64
[[ " $* " == *" --log-format internal-json "* ]] || exit 76
[[ "$*" == *"path:$NIX_ME_TEST_CONFIG#darwinConfigurations.test-host.system"* ]] || exit 65
[[ "$HOSTNAME" == "test-host" ]] || exit 66
[[ "$USERNAME" == "test-user" ]] || exit 67
[[ "$MACHINE_NAME" == "Test Mac" ]] || exit 68
[[ "$MACHINE_TYPE" == "${NIX_ME_TEST_MACHINE_TYPE:-vm}" ]] || exit 69
[[ "$NIX_ME_SOURCE_REVISION" == "abc123" ]] || exit 70
[[ "$SKIP_BREW_ON_VM" == "${NIX_ME_TEST_SKIP_BREW:-1}" ]] || exit 74
[[ "$SKIP_MAS_APPS" == "${NIX_ME_TEST_SKIP_MAS:-1}" ]] || exit 75
printf "building '/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-test-package-1.0.drv'...\n" >&2
jq -n --arg out "$NIX_ME_TEST_SYSTEM" '[{outputs:{out:$out}}]'
SH
cat >"$TEMP_DIR/fake-osascript" <<'SH'
#!/bin/bash
[[ "$*" == *'set activationRunner to systemPath & "/etc/nix-me/activate-system"'* ]] || exit 71
[[ "$*" == *'quoted form of activationRunner & " " & quoted form of systemPath'* ]] || exit 72
[[ " $* " == *" -- $NIX_ME_TEST_SYSTEM test-user "* ]] || exit 73
[[ -z "${NIX_ME_TEST_ACTIVATION_MARKER:-}" ]] || touch "$NIX_ME_TEST_ACTIVATION_MARKER"
printf '%s\n' 'Configuration activated'
SH
chmod +x "$TEMP_DIR/fake-nix" "$TEMP_DIR/fake-osascript"

NIX_ME_CONFIG_DIR="$APPLY_REPO" \
  NIX_ME_ACTION_DRY_RUN=0 \
  NIX_ME_HOSTNAME=test-host \
  NIX_ME_USERNAME=test-user \
  NIX_ME_MACHINE_NAME='Test Mac' \
  NIX_ME_MACHINE_TYPE=vm \
  SKIP_BREW_ON_VM=1 \
  NIX_ME_SOURCE_REVISION=abc123 \
  NIX_ME_NIX_BIN="$TEMP_DIR/fake-nix" \
  NIX_ME_ADMINISTRATOR_RUNNER="$TEMP_DIR/fake-osascript" \
  NIX_ME_TEST_CONFIG="$APPLY_REPO" \
  NIX_ME_TEST_SYSTEM="$APPLY_SYSTEM" \
  "$REPO_DIR/packages/management-api/bin/nix-me-action" apply \
    >"$TEMP_DIR/apply-real.json" 2>"$TEMP_DIR/apply-real-progress.log"
jq -e '
  .schemaVersion == 1 and
  .action == "apply" and
  .success and
  .message == "Configuration applied successfully"
' "$TEMP_DIR/apply-real.json" >/dev/null
grep -Fq $'NIX_ME_PROGRESS\tpreparing\t' "$TEMP_DIR/apply-real-progress.log"
grep -Fq $'NIX_ME_PROGRESS\tbuilding\t' "$TEMP_DIR/apply-real-progress.log"
grep -Fq $'NIX_ME_PROGRESS\tactivating\t' "$TEMP_DIR/apply-real-progress.log"
grep -Fq $'NIX_ME_COMMAND\tbuilding\t' "$TEMP_DIR/apply-real-progress.log"
grep -Fq $'NIX_ME_COMMAND\tactivating\t' "$TEMP_DIR/apply-real-progress.log"
grep -Fq 'test-package-1.0.drv' "$TEMP_DIR/apply-real-progress.log"
! grep -Fq $'NIX_ME_PACKAGE\t' "$TEMP_DIR/apply-real-progress.log"

NIX_ME_CONFIG_DIR="$APPLY_REPO" \
  NIX_ME_ACTION_DRY_RUN=0 \
  NIX_ME_HOSTNAME=test-host \
  NIX_ME_USERNAME=test-user \
  NIX_ME_MACHINE_NAME='Test Mac' \
  NIX_ME_MACHINE_TYPE=macbook-pro \
  SKIP_BREW_ON_VM=0 \
  SKIP_MAS_APPS=0 \
  NIX_ME_SOURCE_REVISION=abc123 \
  NIX_ME_NIX_BIN="$TEMP_DIR/fake-nix" \
  NIX_ME_ADMINISTRATOR_RUNNER="$TEMP_DIR/fake-osascript" \
  NIX_ME_TEST_CONFIG="$APPLY_REPO" \
  NIX_ME_TEST_SYSTEM="$APPLY_SYSTEM" \
  NIX_ME_TEST_MACHINE_TYPE=macbook-pro \
  NIX_ME_TEST_SKIP_BREW=0 \
  NIX_ME_TEST_SKIP_MAS=0 \
  "$REPO_DIR/packages/management-api/bin/nix-me-action" apply \
    >"$TEMP_DIR/apply-packages.json" 2>"$TEMP_DIR/apply-packages-progress.log"
grep -Fq $'NIX_ME_PACKAGE\thomebrew\tqueued\tripgrep\t' "$TEMP_DIR/apply-packages-progress.log"
grep -Fq $'NIX_ME_PACKAGE\thomebrew\tqueued\traycast\t' "$TEMP_DIR/apply-packages-progress.log"
grep -Fq $'NIX_ME_PACKAGE\tmacAppStore\tqueued\tXcode\t' "$TEMP_DIR/apply-packages-progress.log"
activation_line="$(grep -nF $'NIX_ME_PROGRESS\tactivating\t' "$TEMP_DIR/apply-packages-progress.log" | head -1 | cut -d: -f1)"
package_line="$(grep -nF $'NIX_ME_PACKAGE\t' "$TEMP_DIR/apply-packages-progress.log" | head -1 | cut -d: -f1)"
((activation_line < package_line))

ACTIVE_RUNNER="$TEMP_DIR/active-system/etc/nix-me/activate-system"
mkdir -p "$(dirname "$ACTIVE_RUNNER")"
cat >"$ACTIVE_RUNNER" <<'SH'
#!/bin/bash
sleep 30
SH
chmod +x "$ACTIVE_RUNNER"
"$ACTIVE_RUNNER" &
active_runner_pid=$!
for _ in $(seq 1 100); do
  /bin/ps -p "$active_runner_pid" >/dev/null 2>&1 && break
  sleep 0.01
done

NIX_ME_CONFIG_DIR="$APPLY_REPO" \
  NIX_ME_ACTION_DRY_RUN=0 \
  NIX_ME_HOSTNAME=test-host \
  NIX_ME_USERNAME=test-user \
  NIX_ME_MACHINE_NAME='Test Mac' \
  NIX_ME_MACHINE_TYPE=macbook-pro \
  NIX_ME_NIX_BIN="$TEMP_DIR/fake-nix" \
  NIX_ME_ADMINISTRATOR_RUNNER="$TEMP_DIR/fake-osascript" \
  NIX_ME_TEST_NIX_MARKER="$TEMP_DIR/nix-was-called" \
  "$REPO_DIR/packages/management-api/bin/nix-me-action" apply \
    >"$TEMP_DIR/concurrent-apply.json" 2>"$TEMP_DIR/concurrent-apply-progress.log"
kill "$active_runner_pid" >/dev/null 2>&1 || true
wait "$active_runner_pid" 2>/dev/null || true
jq -e '
  .success == false and
  (.message | contains("Another Nix Me activation is already running"))
' "$TEMP_DIR/concurrent-apply.json" >/dev/null
grep -Fq $'NIX_ME_PROGRESS\tpreparing\tAnother system activation is already running' \
  "$TEMP_DIR/concurrent-apply-progress.log"
test ! -e "$TEMP_DIR/nix-was-called"

printf 'pause\n' >"$TEMP_DIR/install-control"
NIX_ME_CONFIG_DIR="$APPLY_REPO" \
  NIX_ME_ACTION_DRY_RUN=0 \
  NIX_ME_HOSTNAME=test-host \
  NIX_ME_USERNAME=test-user \
  NIX_ME_MACHINE_NAME='Test Mac' \
  NIX_ME_MACHINE_TYPE=vm \
  SKIP_BREW_ON_VM=1 \
  NIX_ME_SOURCE_REVISION=abc123 \
  NIX_ME_NIX_BIN="$TEMP_DIR/fake-nix" \
  NIX_ME_ADMINISTRATOR_RUNNER="$TEMP_DIR/fake-osascript" \
  NIX_ME_TEST_CONFIG="$APPLY_REPO" \
  NIX_ME_TEST_SYSTEM="$APPLY_SYSTEM" \
  NIX_ME_TEST_ACTIVATION_MARKER="$TEMP_DIR/activation-started" \
  NIX_ME_INSTALL_CONTROL_FILE="$TEMP_DIR/install-control" \
  "$REPO_DIR/packages/management-api/bin/nix-me-action" apply \
    >"$TEMP_DIR/apply-paused.json" 2>"$TEMP_DIR/apply-paused-progress.log" &
pause_apply_pid=$!
for _ in $(seq 1 100); do
  grep -Fq 'Paused before privileged activation' "$TEMP_DIR/apply-paused-progress.log" && break
  sleep 0.05
done
grep -Fq 'Paused before privileged activation' "$TEMP_DIR/apply-paused-progress.log"
test ! -e "$TEMP_DIR/activation-started"
printf 'running\n' >"$TEMP_DIR/install-control"
wait "$pause_apply_pid"
pause_apply_pid=""
test -e "$TEMP_DIR/activation-started"
jq -e '.success and .action == "apply"' "$TEMP_DIR/apply-paused.json" >/dev/null

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
