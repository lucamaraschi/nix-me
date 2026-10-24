#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

cat >"$TMP_DIR/sudo" <<'EOF'
#!/bin/bash
exec "$@"
EOF

cat >"$TMP_DIR/xcode-select" <<'EOF'
#!/bin/bash
case "$1" in
    --print-path)
        if [ -f "$TEST_STATE/selected" ]; then
            cat "$TEST_STATE/selected"
            exit 0
        fi
        if [ -f "$TEST_STATE/installed" ]; then
            echo /Library/Developer/CommandLineTools
            exit 0
        fi
        exit 1
        ;;
    --switch)
        printf '%s\n' "$2" >"$TEST_STATE/selected"
        ;;
    --install)
        if [ "${TEST_XCODE_SELECT_INSTALLS:-0}" = "1" ]; then
            touch "$TEST_STATE/installed"
            exit 0
        fi
        exit 1
        ;;
esac
EOF

cat >"$TMP_DIR/softwareupdate" <<'EOF'
#!/bin/bash
case "$1" in
    --list)
        if [ "${TEST_SOFTWAREUPDATE_MODE:-unavailable}" != "unavailable" ]; then
            echo '* Label: Command Line Tools for Xcode-26.0'
        else
            echo 'No new software available.'
        fi
        ;;
    --install)
        if [ "${TEST_SOFTWAREUPDATE_MODE:-unavailable}" = "stale" ]; then
            echo "Command Line Tools for Xcode-26.0: No such update"
            echo "No updates are available."
            exit 0
        fi
        printf '%s\n' "$2" >"$TEST_STATE/installed"
        ;;
esac
EOF

chmod +x "$TMP_DIR/sudo" "$TMP_DIR/xcode-select" "$TMP_DIR/softwareupdate"

export PATH="$TMP_DIR:$PATH"
export TEST_STATE="$TMP_DIR/state"
export XCODE_CLI_UPDATE_MARKER="$TMP_DIR/install-on-demand"
export XCODE_APPLICATIONS_DIR="$TMP_DIR/Applications"
export XCODE_COMMAND_LINE_TOOLS_DIR="$TMP_DIR/CommandLineTools"
export NIX_ME_BOOTSTRAPPED=1
mkdir -p "$TEST_STATE"

# shellcheck source=../../install.sh
source "$REPO_DIR/install.sh"

VM_TYPE=traditional-vm
NON_INTERACTIVE=1
SKIP_XCODE_CLT=0

if ensure_xcode_command_line_tools >/dev/null 2>&1; then
    echo "expected unavailable Command Line Tools to fail" >&2
    exit 1
fi

SKIP_XCODE_CLT=1
ensure_xcode_command_line_tools >/dev/null

SKIP_XCODE_CLT=0
TEST_SOFTWAREUPDATE_MODE=available
export TEST_SOFTWAREUPDATE_MODE
ensure_xcode_command_line_tools >/dev/null
grep -q '^Command Line Tools for Xcode-26.0$' "$TEST_STATE/installed"

# An existing full Xcode installation should be selected instead of downloading CLT.
rm -f "$TEST_STATE/installed" "$TEST_STATE/selected"
TEST_SOFTWAREUPDATE_MODE=unavailable
mkdir -p "$XCODE_APPLICATIONS_DIR/Xcode.app/Contents/Developer"
ensure_xcode_command_line_tools >/dev/null
grep -q "$XCODE_APPLICATIONS_DIR/Xcode.app/Contents/Developer" "$TEST_STATE/selected"

# softwareupdate may exit successfully even when a stale catalog label is rejected.
rm -rf "$XCODE_APPLICATIONS_DIR"
rm -f "$TEST_STATE/installed" "$TEST_STATE/selected"
TEST_SOFTWAREUPDATE_MODE=stale
NON_INTERACTIVE=1
if ensure_xcode_command_line_tools >/dev/null 2>&1; then
    echo "expected a stale Command Line Tools update to fail non-interactively" >&2
    exit 1
fi

# Interactive installs recover from a stale catalog through xcode-select.
TEST_XCODE_SELECT_INSTALLS=1
export TEST_XCODE_SELECT_INSTALLS
NON_INTERACTIVE=0
ensure_xcode_command_line_tools >/dev/null
test -f "$TEST_STATE/installed"
NON_INTERACTIVE=1

# The shared prompt helper must select the declared default without reading stdin.
# shellcheck source=../../apps/cli/lib/ui.sh
source "$REPO_DIR/apps/cli/lib/ui.sh"
ask_yes_no "accept default yes" "y"
if ask_yes_no "reject default no" "n"; then
    echo "expected non-interactive default no to return false" >&2
    exit 1
fi

# Command-line installs do not make an app-state choice, so generated hosts must
# leave that option available to profiles such as beta.nix.
# shellcheck source=../../apps/cli/lib/config-builder.sh
source "$REPO_DIR/apps/cli/lib/config-builder.sh"
CONFIG_REPO="$TMP_DIR/config-repo"
mkdir -p "$CONFIG_REPO"
printf '%s\n' '"test-host" =' >"$CONFIG_REPO/flake.nix"
unset WIZARD_APP_STATE_ENABLE
generate_machine_config_multi_profile \
    test-host vm Test tester "$CONFIG_REPO" >/dev/null
HOST_CONFIG="$CONFIG_REPO/nix/hosts/machines/test-host/default.nix"
grep -q 'apps.state.enable inherits' "$HOST_CONFIG"
if grep -q 'apps.state.enable = false' "$HOST_CONFIG"; then
    echo "command-line host unexpectedly disabled app-state profiles" >&2
    exit 1
fi

# /etc/static must remain absent so nix-darwin can create it as a symlink.
if grep -Eq 'mkdir -p .*\/etc\/static' "$REPO_DIR/install.sh"; then
    echo "installer must not create /etc/static as a directory" >&2
    exit 1
fi

# The native setup bundle is disposable only after the app verifies that the
# selected configuration is active. Interrupted setup remains recoverable.
SUCCESSFUL_SETUP_DIR="$TMP_DIR/successful-native-setup"
mkdir -p "$SUCCESSFUL_SETUP_DIR/Nix Me Setup.app"
touch "$SUCCESSFUL_SETUP_DIR/installation-complete"
NIX_ME_LSREGISTER=/usr/bin/true cleanup_native_installer_copy \
    "$SUCCESSFUL_SETUP_DIR" \
    "$SUCCESSFUL_SETUP_DIR/Nix Me Setup.app" \
    "$SUCCESSFUL_SETUP_DIR/installation-complete"
if [ -e "$SUCCESSFUL_SETUP_DIR" ]; then
    echo "successful native setup copy was not removed" >&2
    exit 1
fi

INTERRUPTED_SETUP_DIR="$TMP_DIR/interrupted-native-setup"
mkdir -p "$INTERRUPTED_SETUP_DIR/Nix Me Setup.app"
NIX_ME_LSREGISTER=/usr/bin/true cleanup_native_installer_copy \
    "$INTERRUPTED_SETUP_DIR" \
    "$INTERRUPTED_SETUP_DIR/Nix Me Setup.app" \
    "$INTERRUPTED_SETUP_DIR/installation-complete"
if [ ! -d "$INTERRUPTED_SETUP_DIR/Nix Me Setup.app" ]; then
    echo "interrupted native setup copy should remain available" >&2
    exit 1
fi

echo "install prerequisite and prompt tests passed"
