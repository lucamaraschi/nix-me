#!/bin/bash

# Installation script for Nix/nix-darwin configuration
# Usage: ./install.sh [hostname] [machine-type] [machine-name] [username]
# Environment variables:
#   FORCE_NIX_REINSTALL=1    Force complete Nix reinstall
#   NON_INTERACTIVE=1        Skip confirmation prompts
#   SKIP_BREW_ON_VM=1        Skip Homebrew installation in VMs
#   SKIP_XCODE_CLT=1         Skip Command Line Tools installation in VMs
#   SKIP_MAS_APPS=1          Skip Mac App Store apps (for VMs without iCloud)
#   SKIP_REPO_CLONE=1        Skip git clone/update (use existing files in ~/.config/nixpkgs)
#   XCODE_INSTALL_TIMEOUT_SECONDS=1800
#                            Maximum interactive wait for Command Line Tools
#   USE_WIZARD=1             Enable interactive wizard (default)
#   USE_NATIVE_INSTALLER=1   Continue interactive setup in the macOS app (default)

set -e

# Bootstrap: If running via curl|bash, stdin is consumed by the script.
# We need to download and run the script properly to allow interactive input.
if [ ! -t 0 ] && [ -z "$NIX_ME_BOOTSTRAPPED" ]; then
    echo "Downloading nix-me installer..."
    REPO_BRANCH=${REPO_BRANCH:-main}
    TEMP_SCRIPT=$(mktemp -t nix-me-install.XXXXXX)
    curl -fsSL "https://raw.githubusercontent.com/lucamaraschi/nix-me/${REPO_BRANCH}/install.sh" -o "$TEMP_SCRIPT"
    chmod +x "$TEMP_SCRIPT"
    echo "Starting interactive installer..."
    # Export all env vars and re-run with stdin from terminal
    export NIX_ME_BOOTSTRAPPED=1
    export REPO_BRANCH FORCE_NIX_REINSTALL NON_INTERACTIVE SKIP_BREW_ON_VM SKIP_XCODE_CLT SKIP_MAS_APPS SKIP_REPO_CLONE XCODE_INSTALL_TIMEOUT_SECONDS USE_WIZARD
    bash "$TEMP_SCRIPT" "$@" </dev/tty
    EXIT_CODE=$?
    rm -f "$TEMP_SCRIPT"
    exit $EXIT_CODE
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for better output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions (built-in, no external dependencies)
log() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date '+%H:%M:%S')] ERROR:${NC} $1"
}

info() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')] INFO:${NC} $1"
}

# Fallback UI functions for wizard (used before repo is cloned)
print_header() { echo ""; echo -e "${CYAN}=== $1 ===${NC}"; echo ""; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_info() { echo -e "${BLUE}•${NC} $1"; }
print_warn() { echo -e "${YELLOW}⚠${NC} $1"; }
print_step() { echo -e "${CYAN}[$1]${NC} $2"; }
ask_yes_no() {
    read -p "$(echo -e ${YELLOW}$1 \(Y/n\): ${NC})" answer
    [[ -z $answer || $answer =~ ^[Yy] ]]
}

# Function to test if Nix installation is complete and functional
test_nix_fully_functional() {
    log "Testing Nix installation completeness..."

    # Test 1: Basic binary exists
    if ! command -v nix &>/dev/null; then
        return 1
    fi

    # Test 2: Nix can report its version
    if ! nix --version &>/dev/null 2>&1; then
        warn "Nix binary exists but can't report version"
        return 1
    fi

    # Test 3: Nix daemon is accessible (basic check)
    if ! nix-instantiate --eval -E 'builtins.currentTime' &>/dev/null 2>&1; then
        warn "Nix daemon not responding to commands"
        return 1
    fi

    # Test 4: Flakes are working (needed for our config)
    if ! nix flake --help &>/dev/null 2>&1; then
        warn "Nix flakes not available"
        return 1
    fi

    log "Nix installation appears functional"
    return 0
}

# Function to completely uninstall Nix
uninstall_nix() {
    warn "Uninstalling existing Nix installation..."

    # Method 1: Use Determinate Systems uninstaller (primary method)
    if [ -f /nix/nix-installer ]; then
        log "Using Determinate Systems uninstaller"
        sudo /nix/nix-installer uninstall || {
            warn "Determinate Systems uninstaller failed, continuing with manual cleanup"
        }
    fi

    # Method 2: Use legacy uninstaller if it exists
    if [ -f /nix/uninstall ]; then
        log "Using legacy Nix uninstaller"
        sudo /nix/uninstall || warn "Legacy uninstaller had issues, continuing with manual cleanup"
    fi

    # Method 3: Manual cleanup (comprehensive)
    log "Performing manual Nix cleanup..."

    # Stop and remove nix-daemon
    sudo launchctl unload /Library/LaunchDaemons/org.nixos.nix-daemon.plist 2>/dev/null || true
    sudo rm -f /Library/LaunchDaemons/org.nixos.nix-daemon.plist

    # Remove Nix store and configuration
    log "Removing Nix store and configuration..."
    sudo rm -rf /nix || warn "Could not remove /nix directory"
    sudo rm -rf /etc/nix || warn "Could not remove /etc/nix directory"

    # Remove synthetic.conf entries
    if [ -f /etc/synthetic.conf ]; then
        sudo sed -i.backup '/^nix$/d' /etc/synthetic.conf 2>/dev/null || true
    fi

    # Remove fstab entries
    if [ -f /etc/fstab ]; then
        sudo sed -i.backup '/nix/d' /etc/fstab 2>/dev/null || true
    fi

    # Remove user-level Nix
    rm -rf ~/.nix-* 2>/dev/null || true
    rm -rf ~/.config/nix 2>/dev/null || true
    rm -rf ~/.cache/nix 2>/dev/null || true

    # Remove nix users and group
    for i in $(seq 1 32); do
        sudo dscl . -delete /Users/_nixbld$i 2>/dev/null || true
    done
    sudo dscl . -delete /Groups/nixbld 2>/dev/null || true

    # Verify cleanup
    if [ -f /nix/receipt.json ]; then
        sudo rm -f /nix/receipt.json || {
            error "Could not remove existing receipt.json"
            return 1
        }
    fi

    log "Nix successfully uninstalled"
    return 0
}

# Function to safely update git repository
safe_git_update() {
    local repo_dir="$1"
    local repo_branch="$2"

    log "Safely updating git repository..."

    cd "$repo_dir"

    # Fetch latest changes without rewriting local work.
    git fetch origin || {
        error "Failed to fetch from remote repository"
        return 1
    }

    local current_branch
    current_branch=$(git branch --show-current)
    if [ -z "$current_branch" ]; then
        git checkout "$repo_branch" 2>/dev/null || git checkout -b "$repo_branch" "origin/$repo_branch"
        current_branch="$repo_branch"
    fi

    if [ "$current_branch" != "$repo_branch" ]; then
        warn "Configuration is on branch $current_branch; leaving it unchanged"
        return 0
    fi

    log "Rebasing local work onto origin/$repo_branch..."
    git pull --rebase --autostash origin "$repo_branch" || {
        error "Could not update without rewriting local work"
        error "Resolve the Git state in $repo_dir, then run the installer again"
        return 1
    }

    log "Repository successfully updated to latest remote state"
}

launch_native_installer() {
    local repo_dir="$1"
    local setup_output setup_app setup_log

    print_header "Continue in Nix Me"
    print_info "Building a lightweight local setup app. This does not require notarization."
    setup_log=$(mktemp "${TMPDIR:-/tmp}/nix-me-setup.XXXXXX")
    setup_output=$(nix --extra-experimental-features "nix-command flakes" \
        build --no-link --print-out-paths "path:$repo_dir#nix-me-setup" 2>"$setup_log") || {
        error "Could not build the Nix Me setup app"
        tail -80 "$setup_log" >&2 || true
        rm -f "$setup_log"
        return 1
    }
    rm -f "$setup_log"
    setup_app="$setup_output/Applications/Nix Me Setup.app"
    if [ ! -d "$setup_app" ]; then
        error "The setup app was not found at $setup_app"
        return 1
    fi

    defaults write com.nix-me.manager NixMeConfigurationDirectory "$repo_dir"
    if ! open "$setup_app" --args --first-install; then
        error "macOS could not open Nix Me Setup"
        return 1
    fi

    echo ""
    print_success "Nix Me is open"
    print_info "Choose the profiles for this Mac, review the plan, and apply it from the app."
    print_info "You can close this terminal window."
}

# Function to ensure Homebrew is properly installed and in PATH
ensure_homebrew() {
    # Skip homebrew on VMs if requested
    if [ "$VM_TYPE" != "physical" ] && [ "$SKIP_BREW_ON_VM" = "1" ]; then
        log "Skipping Homebrew installation in VM environment"
        return 0
    fi

    # Check if brew command is available
    if command -v brew &>/dev/null; then
        log "Homebrew is available in PATH"
        return 0
    fi

    # Try to find and source Homebrew
    if [[ -f /opt/homebrew/bin/brew ]]; then
        log "Found Homebrew (Apple Silicon), adding to PATH"
        export PATH="/opt/homebrew/bin:$PATH"
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -f /usr/local/bin/brew ]]; then
        log "Found Homebrew (Intel), adding to PATH"
        export PATH="/usr/local/bin:$PATH"
        eval "$(/usr/local/bin/brew shellenv)"
    else
        log "Installing Homebrew..."
        # Use NONINTERACTIVE=1 to skip confirmation prompts
        NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

        # Set up PATH after installation
        if [[ -f /opt/homebrew/bin/brew ]]; then
            export PATH="/opt/homebrew/bin:$PATH"
            eval "$(/opt/homebrew/bin/brew shellenv)"
        elif [[ -f /usr/local/bin/brew ]]; then
            export PATH="/usr/local/bin:$PATH"
            eval "$(/usr/local/bin/brew shellenv)"
        else
            error "Homebrew installation failed"
            return 1
        fi
    fi

    # Verify brew is now available
    if ! command -v brew &>/dev/null; then
        error "Homebrew installation appears successful but 'brew' command not found"
        return 1
    fi

    log "Updating Homebrew..."
    brew update

    return 0
}

xcode_cli_tools_ready() {
    xcode-select --print-path &>/dev/null
}

select_existing_xcode_developer_directory() {
    local applications_dir="${XCODE_APPLICATIONS_DIR:-/Applications}"
    local command_line_tools_dir="${XCODE_COMMAND_LINE_TOOLS_DIR:-/Library/Developer/CommandLineTools}"
    local candidate

    # A full Xcode installation is sufficient and avoids downloading CLT again.
    for candidate in "$applications_dir"/Xcode*.app/Contents/Developer "$command_line_tools_dir"; do
        if [ ! -d "$candidate" ]; then
            continue
        fi

        log "Selecting existing developer tools at $candidate..."
        if sudo xcode-select --switch "$candidate" >/dev/null 2>&1 && xcode_cli_tools_ready; then
            return 0
        fi
    done

    return 1
}

find_xcode_cli_tools_update() {
    local marker="${XCODE_CLI_UPDATE_MARKER:-/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress}"
    local updates

    sudo touch "$marker"
    updates=$(softwareupdate --list 2>&1 || true)
    sudo rm -f "$marker"

    printf '%s\n' "$updates" \
        | sed -n 's/^[[:space:]]*\* Label: \(Command Line Tools.*\)$/\1/p' \
        | tail -n 1
}

install_xcode_cli_tools_update() {
    local update_label="$1"
    local output_file
    local status=0

    output_file=$(mktemp -t nix-me-xcode-clt.XXXXXX)
    sudo softwareupdate --install "$update_label" --verbose >"$output_file" 2>&1 || status=$?
    cat "$output_file"
    rm -f "$output_file"

    if xcode_cli_tools_ready || select_existing_xcode_developer_directory; then
        return 0
    fi

    if [ "$status" -ne 0 ]; then
        warn "softwareupdate exited with code $status without installing Command Line Tools"
    else
        warn "softwareupdate finished, but Command Line Tools are still unavailable"
    fi
    return 1
}

request_xcode_cli_tools_interactively() {
    local timeout_seconds=${XCODE_INSTALL_TIMEOUT_SECONDS:-1800}
    local elapsed=0

    log "Opening the Command Line Tools installer..."
    xcode-select --install 2>/dev/null || true

    echo ""
    echo "    ╔════════════════════════════════════════════════════════════╗"
    echo "    ║  A dialog will appear to install Command Line Tools.       ║"
    echo "    ║  Please click 'Install' and wait for it to complete.       ║"
    echo "    ╚════════════════════════════════════════════════════════════╝"
    echo ""

    log "Waiting up to ${timeout_seconds}s for installation to complete..."
    while ! xcode_cli_tools_ready; do
        if select_existing_xcode_developer_directory; then
            return 0
        fi
        if [ "$elapsed" -ge "$timeout_seconds" ]; then
            error "Timed out waiting for Command Line Tools after ${timeout_seconds}s"
            error "Install them manually with 'xcode-select --install', then run the installer again"
            return 1
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done
}

ensure_xcode_command_line_tools() {
    if xcode_cli_tools_ready; then
        return 0
    fi

    if [ "$VM_TYPE" != "physical" ] && [ "$SKIP_XCODE_CLT" = "1" ]; then
        warn "Skipping Xcode Command Line Tools in VM environment"
        return 0
    fi

    if select_existing_xcode_developer_directory; then
        return 0
    fi

    local update_label
    update_label=$(find_xcode_cli_tools_update)
    if [ -n "$update_label" ]; then
        log "Installing $update_label with softwareupdate..."
        if install_xcode_cli_tools_update "$update_label"; then
            return 0
        fi

        # The software update catalog can change between listing and installing.
        local refreshed_label
        refreshed_label=$(find_xcode_cli_tools_update)
        if [ -n "$refreshed_label" ] && [ "$refreshed_label" != "$update_label" ]; then
            log "Retrying with refreshed update $refreshed_label..."
            if install_xcode_cli_tools_update "$refreshed_label"; then
                return 0
            fi
        fi
    fi

    if [ "$NON_INTERACTIVE" = "1" ]; then
        if [ -n "$update_label" ]; then
            error "macOS Software Update advertised '$update_label', but it could not be installed"
        else
            error "Command Line Tools are not installed and macOS Software Update does not offer them"
        fi
        error "Update macOS or install Command Line Tools manually, then run the installer again"
        error "Disposable VMs may use SKIP_XCODE_CLT=1 together with SKIP_BREW_ON_VM=1"
        return 1
    fi

    if ! request_xcode_cli_tools_interactively || ! xcode_cli_tools_ready; then
        error "Command Line Tools installation completed without an active developer directory"
        return 1
    fi

    return 0
}

# Enhanced Nix installation function
install_or_fix_nix() {
    # Existing installations are not visible to every non-interactive shell.
    if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
        source '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
    fi
    export PATH=$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$PATH

    # Check if we should force reinstall
    if [ "$FORCE_NIX_REINSTALL" = "1" ]; then
        log "Force reinstall requested, uninstalling existing Nix..."
        if command -v nix &>/dev/null; then
            uninstall_nix || return 1
        fi
    elif command -v nix &>/dev/null; then
        # Nix binary exists, test if it's fully functional
        if test_nix_fully_functional; then
            log "Nix is already installed and functional"
            return 0
        else
            warn "Nix is installed but not fully functional"

            # Try simple fixes first
            log "Attempting to repair Nix installation..."

            # Try restarting daemon
            if [ -e "/Library/LaunchDaemons/org.nixos.nix-daemon.plist" ]; then
                sudo launchctl unload /Library/LaunchDaemons/org.nixos.nix-daemon.plist 2>/dev/null || true
                sudo launchctl load /Library/LaunchDaemons/org.nixos.nix-daemon.plist
                sleep 3

                if test_nix_fully_functional; then
                    log "Successfully repaired Nix installation"
                    return 0
                fi
            fi

            # Simple fixes failed, need to reinstall
            warn "Cannot repair Nix installation - will uninstall and reinstall"

            # Ask user for confirmation unless in non-interactive mode
            if [ "$NON_INTERACTIVE" != "1" ]; then
                if ! ask_yes_no "Nix installation appears broken. Reinstall?"; then
                    error "User declined reinstall. Cannot continue."
                    error "To force reinstall, run: FORCE_NIX_REINSTALL=1 $0"
                    return 1
                fi
            fi

            # Uninstall broken Nix
            uninstall_nix || return 1
        fi
    fi

    # Install fresh Nix
    log "Installing Nix using Determinate Systems installer..."

    # Use --no-confirm for non-interactive installation
    if [ "$NON_INTERACTIVE" = "1" ]; then
        curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --no-confirm
    else
        curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
    fi

    # Source environment
    if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
        source '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
    fi

    # Update PATH for current session
    export PATH=$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$PATH

    # Give the daemon a moment to fully start
    sleep 3

    # Basic functionality test
    if command -v nix &>/dev/null && nix --version &>/dev/null && nix-instantiate --eval -E '1 + 1' &>/dev/null; then
        log "Nix installation completed successfully"
        return 0
    else
        error "Nix installation failed basic verification"
        return 1
    fi
}

# Function to detect virtual machine environment
detect_vm_environment() {
    local hardware_info=$(system_profiler SPHardwareDataType 2>/dev/null)

    # Check for explicit VM indicators in hardware
    if echo "$hardware_info" | grep -i "virtual\|parallels\|vmware\|virtualbox" > /dev/null; then
        echo "traditional-vm"
        return
    fi

    # Check for Apple Virtual Machine
    if echo "$hardware_info" | grep -i "Apple Virtual Machine" > /dev/null; then
        echo "apple-vm"
        return
    fi

    # Check hardware model for VM indicators
    local model=$(sysctl -n hw.model 2>/dev/null)
    if echo "$model" | grep -i "virtual" > /dev/null; then
        echo "vm-hardware"
        return
    fi

    echo "physical"
}

# Simple wizard for first-time setup (no external dependencies)
run_simple_wizard() {
    local repo_dir="$1"

    print_header "nix-me Setup Wizard"

    # Check if this is an update to existing config
    if [ -d "$repo_dir" ] && [ -f "$repo_dir/flake.nix" ]; then
        print_info "Existing configuration detected"
        if ask_yes_no "Would you like to modify an existing machine configuration?"; then
            # For updates, try to use the full wizard if available
            if [ -f "$repo_dir/apps/cli/lib/wizard.sh" ]; then
                source "$repo_dir/apps/cli/lib/ui.sh" 2>/dev/null || true
                source "$repo_dir/apps/cli/lib/wizard.sh"

                if run_setup_wizard "$repo_dir" && [ "$WIZARD_SUCCESS" == "1" ]; then
                    if [ "${WIZARD_MODIFY_ONLY:-0}" == "1" ]; then
                        print_success "Configuration updated for: $WIZARD_HOSTNAME"
                        print_info "Run 'make switch' to apply changes"
                        exit 0
                    fi

                    # Export wizard values
                    export WIZARD_HOSTNAME WIZARD_MACHINE_TYPE WIZARD_MACHINE_NAME WIZARD_USERNAME WIZARD_CONFIG_PROFILE WIZARD_SELECTED_HOST
                    return 0
                else
                    print_error "Setup cancelled"
                    exit 1
                fi
            fi
        fi
    fi

    # Fresh installation - use simple prompts
    print_info "This wizard will help you set up your nix-me configuration"
    echo ""

    # Get hostname
    local default_hostname
    if [ "$VM_TYPE" != "physical" ]; then
        default_hostname="nix-darwin-vm"
    else
        default_hostname=$(hostname -s | tr '[:upper:]' '[:lower:]')
    fi

    read -p "$(echo -e ${CYAN}Hostname ${NC}[${default_hostname}]: )" input_hostname
    WIZARD_HOSTNAME=${input_hostname:-$default_hostname}

    # Get machine type
    local default_type
    if [ "$VM_TYPE" != "physical" ]; then
        default_type="vm"
    else
        default_type="macbook"
    fi

    print_info "Machine types: macbook, macmini, vm"
    read -p "$(echo -e ${CYAN}Machine Type ${NC}[${default_type}]: )" input_type
    WIZARD_MACHINE_TYPE=${input_type:-$default_type}

    # Get machine name
    local default_name="$WIZARD_HOSTNAME"
    read -p "$(echo -e ${CYAN}Machine Name ${NC}[${default_name}]: )" input_name
    WIZARD_MACHINE_NAME=${input_name:-$default_name}

    # Get username
    local default_user=$(whoami)
    read -p "$(echo -e ${CYAN}Username ${NC}[${default_user}]: )" input_user
    WIZARD_USERNAME=${input_user:-$default_user}

    # Get config profile
    WIZARD_CONFIG_PROFILE="standard"

    echo ""
    print_header "Configuration Summary"
    echo "  Hostname:     $WIZARD_HOSTNAME"
    echo "  Type:         $WIZARD_MACHINE_TYPE"
    echo "  Name:         $WIZARD_MACHINE_NAME"
    echo "  Username:     $WIZARD_USERNAME"
    echo ""

    if ! ask_yes_no "Proceed with this configuration?"; then
        print_error "Setup cancelled"
        exit 1
    fi

    export WIZARD_HOSTNAME WIZARD_MACHINE_TYPE WIZARD_MACHINE_NAME WIZARD_USERNAME WIZARD_CONFIG_PROFILE
    return 0
}

# Main installation function
main() {
    # Control variables
    FORCE_NIX_REINSTALL=${FORCE_NIX_REINSTALL:-0}
    NON_INTERACTIVE=${NON_INTERACTIVE:-0}
    SKIP_BREW_ON_VM=${SKIP_BREW_ON_VM:-0}
    SKIP_XCODE_CLT=${SKIP_XCODE_CLT:-0}
    SKIP_MAS_APPS=${SKIP_MAS_APPS:-0}
    USE_WIZARD=${USE_WIZARD:-1}
    USE_NATIVE_INSTALLER=${USE_NATIVE_INSTALLER:-1}

    REPO_URL=${REPO_URL:-"https://github.com/lucamaraschi/nix-me.git"}
    REPO_BRANCH=${REPO_BRANCH:-"main"}
    REPO_DIR=${HOME}/.config/nixpkgs
    NATIVE_INSTALL_FLOW=0
    if [ $# -eq 0 ] && [ "$NON_INTERACTIVE" != "1" ] && [ "$USE_NATIVE_INSTALLER" = "1" ]; then
        NATIVE_INSTALL_FLOW=1
    fi
    STEP_TOTAL=7
    [ "$NATIVE_INSTALL_FLOW" = "1" ] && STEP_TOTAL=5

    print_header "nix-me Installation"
    if [ "$NATIVE_INSTALL_FLOW" = "1" ]; then
        print_info "This terminal prepares the trusted system tools only."
        print_info "Machine choices, build progress, and recovery continue in the Nix Me app."
        echo ""
    fi

    # Verify macOS
    if [[ "$OSTYPE" != "darwin"* ]]; then
        error "This script must be run on macOS"
        exit 1
    fi

    # Detect environment
    VM_TYPE=$(detect_vm_environment)
    log "Detected environment: ${VM_TYPE}"

    # STEP 1: Request sudo privileges (keep alive throughout)
    print_step "1/$STEP_TOTAL" "Requesting Administrator Privileges"
    if sudo -n true 2>/dev/null; then
        log "Passwordless sudo is configured"
    else
        sudo -v || { error "Authentication failed"; exit 1; }
    fi
    # Keep sudo alive in background
    ( while true; do sudo -n -v 2>/dev/null; sleep 30; done ) &
    SUDO_REFRESH_PID=$!
    trap "kill $SUDO_REFRESH_PID 2>/dev/null || true" EXIT
    log "Sudo credentials will be kept alive during installation"
    print_success "Administrator access granted"
    echo ""

    # STEP 2: Install Xcode CLI tools (needed for git)
    print_step "2/$STEP_TOTAL" "Installing Xcode Command Line Tools"
    ensure_xcode_command_line_tools || exit 1
    print_success "Xcode Command Line Tools ready"

    # Accept Xcode license only if full Xcode.app is installed
    # (xcodebuild requires Xcode.app, not just Command Line Tools)
    if [ -d "/Applications/Xcode.app" ]; then
        if ! sudo xcodebuild -license status &>/dev/null 2>&1; then
            log "Accepting Xcode license..."
            sudo xcodebuild -license accept 2>/dev/null || true
        fi
    fi
    echo ""

    # STEP 3: Clone/update repository so wizard can see existing hosts
    print_step "3/$STEP_TOTAL" "Setting up Configuration Repository"
    if [ "${SKIP_REPO_CLONE:-0}" = "1" ]; then
        log "Skipping git clone/update (SKIP_REPO_CLONE=1)"
        if [ ! -d "$REPO_DIR" ]; then
            error "SKIP_REPO_CLONE=1 but $REPO_DIR does not exist"
            exit 1
        fi
        log "Using existing files in $REPO_DIR"
    elif [ -d "$REPO_DIR" ]; then
        log "Repository exists, safely updating..."
        safe_git_update "$REPO_DIR" "$REPO_BRANCH" || {
            error "Failed to update repository"
            exit 1
        }
    else
        log "Cloning configuration repository..."
        mkdir -p "$(dirname "$REPO_DIR")"
        git clone "$REPO_URL" "$REPO_DIR" || {
            error "Failed to clone repository"
            exit 1
        }
        cd "$REPO_DIR"
        git checkout "$REPO_BRANCH"
    fi
    mkdir -p "$REPO_DIR/lib" "$REPO_DIR/bin"
    print_success "Repository ready"
    echo ""

    # STEP 4: Run wizard (now that repo is available with existing hosts)
    if [ "$NATIVE_INSTALL_FLOW" != "1" ]; then
        print_step "4/7" "Configuration Wizard"
    fi
    if [ "$NATIVE_INSTALL_FLOW" = "1" ]; then
        HOST_NAME=$(hostname -s | tr '[:upper:]' '[:lower:]')
        MACHINE_TYPE=""
        MACHINE_NAME="$HOST_NAME"
        NIXOS_USERNAME=$(whoami)
        CONFIG_PROFILE="native"
        print_info "The native setup assistant will configure this Mac after prerequisites are ready"
    elif [ $# -eq 0 ] && [ "$NON_INTERACTIVE" != "1" ] && [ "$USE_WIZARD" == "1" ]; then
        # Use full wizard if available (it can see existing hosts now)
        if [ -f "$REPO_DIR/apps/cli/lib/wizard.sh" ] && [ -f "$REPO_DIR/apps/cli/lib/ui.sh" ]; then
            source "$REPO_DIR/apps/cli/lib/ui.sh"
            source "$REPO_DIR/apps/cli/lib/wizard.sh"
            if run_setup_wizard "$REPO_DIR"; then
                HOST_NAME=${WIZARD_HOSTNAME}
                MACHINE_TYPE=${WIZARD_MACHINE_TYPE}
                MACHINE_NAME=${WIZARD_MACHINE_NAME}
                NIXOS_USERNAME=${WIZARD_USERNAME}
                CONFIG_PROFILE=${WIZARD_CONFIG_PROFILE:-standard}
            else
                error "Setup wizard cancelled"
                exit 1
            fi
        else
            # Fallback to simple wizard
            run_simple_wizard "$REPO_DIR"
            HOST_NAME=${WIZARD_HOSTNAME}
            MACHINE_TYPE=${WIZARD_MACHINE_TYPE}
            MACHINE_NAME=${WIZARD_MACHINE_NAME}
            NIXOS_USERNAME=${WIZARD_USERNAME}
            CONFIG_PROFILE=${WIZARD_CONFIG_PROFILE:-standard}
        fi
    else
        # Command-line arguments or non-interactive mode
        if [ -z "$1" ]; then
            if [ "$VM_TYPE" != "physical" ]; then
                HOST_NAME="nix-darwin-vm"
            else
                HOST_NAME=$(hostname -s | tr '[:upper:]' '[:lower:]')
            fi
        else
            HOST_NAME=$1
        fi

        MACHINE_TYPE=${2:-""}
        MACHINE_NAME=${3:-"$HOST_NAME"}
        NIXOS_USERNAME=${4:-$(whoami)}
        CONFIG_PROFILE="standard"

        # Auto-detect machine type if not provided
        if [[ -z "$MACHINE_TYPE" ]]; then
            if [ "$VM_TYPE" != "physical" ]; then
                MACHINE_TYPE="vm"
            elif [[ "$HOST_NAME" == *"macbook"* || "$HOST_NAME" == *"mba"* ]]; then
                MACHINE_TYPE="macbook"
            elif [[ "$HOST_NAME" == *"mini"* ]]; then
                MACHINE_TYPE="macmini"
            else
                MACHINE_TYPE="macbook"
            fi
            log "Auto-detected machine type: $MACHINE_TYPE"
        fi
    fi

    # Set HOST environment variable
    export HOST="$HOST_NAME"

    if [ "$NATIVE_INSTALL_FLOW" != "1" ]; then
        # Display configuration for CLI-driven installs. The native flow owns
        # this review when it is active.
        print_header "Installation Configuration"
        echo ""
        echo "  Hostname:       $HOST_NAME"
        echo "  Machine Type:   $MACHINE_TYPE"
        echo "  Machine Name:   $MACHINE_NAME"
        echo "  Username:       $NIXOS_USERNAME"
        echo "  Profile:        $CONFIG_PROFILE"
        echo "  Environment:    $VM_TYPE"
        echo "  Repository:     $REPO_URL"
        echo "  Branch:         $REPO_BRANCH"
        echo ""

        if [ "$NON_INTERACTIVE" != "1" ] && [ $# -gt 0 ]; then
            if ! ask_yes_no "Continue with installation?"; then
                error "Installation cancelled"
                exit 1
            fi
        fi
    fi

    # STEP 5: Ensure Homebrew
    if [ "$NATIVE_INSTALL_FLOW" = "1" ]; then
        print_step "4/$STEP_TOTAL" "Setting up Homebrew"
    else
        print_step "5/$STEP_TOTAL" "Setting up Homebrew"
    fi
    ensure_homebrew || {
        error "Failed to set up Homebrew"
        exit 1
    }
    print_success "Homebrew ready"
    echo ""

    # STEP 6: Install or fix Nix
    if [ "$NATIVE_INSTALL_FLOW" = "1" ]; then
        print_step "5/$STEP_TOTAL" "Installing Nix Package Manager"
    else
        print_step "6/$STEP_TOTAL" "Installing Nix Package Manager"
    fi
    install_or_fix_nix || {
        error "Failed to install or fix Nix"
        exit 1
    }
    export PATH=$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$PATH
    print_success "Nix installed and configured"
    echo ""

    if [ "$NATIVE_INSTALL_FLOW" = "1" ]; then
        launch_native_installer "$REPO_DIR" || exit 1
        exit 0
    fi

    # STEP 7: Generate machine configuration and build
    print_step "7/$STEP_TOTAL" "Building and Activating System"
    cd "$REPO_DIR"

    # Generate config only if creating new (not selecting existing host)
    if [ -n "$WIZARD_SELECTED_HOST" ]; then
        log "Using existing configuration: $WIZARD_SELECTED_HOST"
    elif [ -f "$REPO_DIR/apps/cli/lib/config-builder.sh" ]; then
        log "Generating machine configuration..."
        source "$REPO_DIR/apps/cli/lib/config-builder.sh"
        generate_machine_config "$HOST_NAME" "$MACHINE_TYPE" "$MACHINE_NAME" "$NIXOS_USERNAME" "$REPO_DIR" "0"
    else
        warn "Config builder not available, ensure machine is in flake.nix"
    fi

    # Enable flakes
    mkdir -p ~/.config/nix
    echo "experimental-features = nix-command flakes" > ~/.config/nix/nix.conf

    # Configure Claude Code settings
    log "Configuring Claude Code settings..."
    mkdir -p ~/.claude
    cat > ~/.claude/settings.json <<'EOF'
{
  "includeCoAuthoredBy": false
}
EOF

    # Configure VS Code workspace settings
    if [ -d "${REPO_DIR}/config/vscode" ]; then
        log "Configuring VS Code workspace settings..."
        mkdir -p "${REPO_DIR}/.vscode"
        cp -r "${REPO_DIR}/config/vscode/"* "${REPO_DIR}/.vscode/"
        print_success "VS Code configuration installed"
    fi
    log "Building system configuration (this may take 15-30 minutes)..."
    # Export USERNAME for flake.nix to read (with --impure flag)
    export USERNAME="$NIXOS_USERNAME"

    # Backup /etc files that nix-darwin needs to manage
    for etc_file in /etc/shells /etc/zshenv /etc/zshrc /etc/bashrc; do
        if [ -f "$etc_file" ] && [ ! -L "$etc_file" ]; then
            if ! grep -q "nix-darwin" "$etc_file" 2>/dev/null; then
                if [ -e "${etc_file}.before-nix-darwin" ]; then
                    log "Removing regenerated $etc_file; preserving existing backup"
                    sudo rm "$etc_file"
                else
                    log "Backing up $etc_file to ${etc_file}.before-nix-darwin"
                    sudo mv "$etc_file" "${etc_file}.before-nix-darwin"
                fi
            fi
        fi
    done

    if ! command -v darwin-rebuild &>/dev/null; then
        log "Installing nix-darwin..."
        nix build --extra-experimental-features "nix-command flakes" --impure \
            ".#darwinConfigurations.$HOST_NAME.system"
        # nix-darwin creates /etc/static as a symlink during activation.
        sudo mkdir -p /etc/nix-darwin
        # Use sudo env to preserve USERNAME through sudo
        sudo env \
            USERNAME="$NIXOS_USERNAME" \
            SKIP_BREW_ON_VM="$SKIP_BREW_ON_VM" \
            SKIP_MAS_APPS="$SKIP_MAS_APPS" \
            PATH="$PATH" \
            ./result/sw/bin/darwin-rebuild switch --flake ".#$HOST_NAME" --impure
    else
        log "Activating configuration..."
        # Use sudo env to preserve USERNAME through sudo
        sudo env \
            USERNAME="$NIXOS_USERNAME" \
            SKIP_BREW_ON_VM="$SKIP_BREW_ON_VM" \
            SKIP_MAS_APPS="$SKIP_MAS_APPS" \
            PATH="$PATH" \
            darwin-rebuild switch --flake ".#$HOST_NAME" --impure
    fi

    echo ""
    print_success "Installation complete!"

    # Print final instructions
    echo ""
    print_header "🎉 Welcome to nix-me!"
    echo ""
    echo "  Your macOS system is now managed with Nix."
    echo ""
    echo -e "  ${GREEN}Next Steps:${NC}"
    echo -e "  1. Run: ${CYAN}nix-me doctor${NC} (check system health)"
    echo -e "  2. Run: ${CYAN}nix-me customize${NC} (add more apps)"
    echo -e "  3. Run: ${CYAN}nix-me --help${NC} (see all commands)"
    echo ""
    echo -e "  ${YELLOW}Useful Commands:${NC}"
    echo -e "  • ${CYAN}nix-me add app <name>${NC}  - Search and add GUI apps"
    echo -e "  • ${CYAN}nix-me add tool <name>${NC} - Add CLI tools"
    echo -e "  • ${CYAN}nix-me setup${NC}           - Re-run setup wizard"
    echo -e "  • ${CYAN}nix-me switch${NC}          - Apply configuration changes"
    echo ""
    echo -e "  ${GREEN}Configuration:${NC} ${REPO_DIR}"
    echo ""

    if [ "$NON_INTERACTIVE" = "1" ]; then
        echo -e "  ${YELLOW}Open a new shell to pick up the managed environment.${NC}"
    else
        echo -e "  ${YELLOW}Restarting shell...${NC}"
        exec "$SHELL"
    fi
}

# Run main function unless this file is sourced by a test or helper.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
