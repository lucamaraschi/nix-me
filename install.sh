#!/bin/bash

# Installation script for Nix/nix-darwin configuration
# Usage: ./install.sh [hostname] [machine-type] [machine-name] [username]
# Environment variables:
#   FORCE_NIX_REINSTALL=1    Force complete Nix reinstall
#   NON_INTERACTIVE=1        Skip confirmation prompts
#   SKIP_BREW_ON_VM=1        Skip Homebrew installation in VMs
#   SKIP_MAS_APPS=1          Skip Mac App Store apps (for VMs without iCloud)
#   SKIP_REPO_CLONE=1        Skip git clone/update (use existing files in ~/.config/nixpkgs)
#   USE_WIZARD=1             Enable interactive wizard (default)

set -e

# Bootstrap: If running via curl|bash, stdin is consumed by the script.
# We need to download and run the script properly to allow interactive input.
if [ ! -t 0 ] && [ -z "$NIX_ME_BOOTSTRAPPED" ]; then
    echo "Downloading nix-me installer..."
    REPO_BRANCH=${REPO_BRANCH:-main}
    TEMP_SCRIPT=$(mktemp)
    curl -fsSL "https://raw.githubusercontent.com/lucamaraschi/nix-me/${REPO_BRANCH}/install.sh" -o "$TEMP_SCRIPT"
    chmod +x "$TEMP_SCRIPT"
    echo "Starting interactive installer..."
    # Re-run with stdin from terminal and mark as bootstrapped
    NIX_ME_BOOTSTRAPPED=1 exec "$TEMP_SCRIPT" "$@" </dev/tty
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

    # Fetch latest changes
    git fetch origin || {
        error "Failed to fetch from remote repository"
        return 1
    }

    # Check if we have local changes
    if ! git diff --quiet HEAD; then
        warn "Local changes detected in repository"
        log "Stashing local changes..."
        git stash push -m "install.sh auto-stash $(date)" || true
    fi

    # Force reset to remote state
    log "Resetting to remote state..."
    git checkout "$repo_branch" 2>/dev/null || git checkout -b "$repo_branch" origin/"$repo_branch"
    git reset --hard origin/"$repo_branch"

    log "Repository successfully updated to latest remote state"
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

# Enhanced Nix installation function
install_or_fix_nix() {
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
            if [ -f "$repo_dir/lib/wizard.sh" ]; then
                source "$repo_dir/lib/ui.sh" 2>/dev/null || true
                source "$repo_dir/lib/wizard.sh"

                if run_setup_wizard "$repo_dir" && [ "$WIZARD_SUCCESS" == "1" ]; then
                    if [ "${WIZARD_MODIFY_ONLY:-0}" == "1" ]; then
                        print_success "Configuration updated for: $WIZARD_HOSTNAME"
                        print_info "Run 'make switch' to apply changes"
                        exit 0
                    fi

                    # Export wizard values
                    export WIZARD_HOSTNAME WIZARD_MACHINE_TYPE WIZARD_MACHINE_NAME WIZARD_USERNAME WIZARD_CONFIG_PROFILE
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
    USE_WIZARD=${USE_WIZARD:-1}

    REPO_URL=${REPO_URL:-"https://github.com/lucamaraschi/nix-me.git"}
    REPO_BRANCH=${REPO_BRANCH:-"main"}
    REPO_DIR=${HOME}/.config/nixpkgs

    print_header "nix-me Installation"

    # Verify macOS
    if [[ "$OSTYPE" != "darwin"* ]]; then
        error "This script must be run on macOS"
        exit 1
    fi

    # Detect environment
    VM_TYPE=$(detect_vm_environment)
    log "Detected environment: ${VM_TYPE}"

    # STEP 1: Run wizard FIRST (if appropriate and no args provided)
    if [ $# -eq 0 ] && [ "$NON_INTERACTIVE" != "1" ] && [ "$USE_WIZARD" == "1" ]; then
        run_simple_wizard "$REPO_DIR"

        # Use wizard values
        HOST_NAME=${WIZARD_HOSTNAME}
        MACHINE_TYPE=${WIZARD_MACHINE_TYPE}
        MACHINE_NAME=${WIZARD_MACHINE_NAME}
        NIXOS_USERNAME=${WIZARD_USERNAME}
        CONFIG_PROFILE=${WIZARD_CONFIG_PROFILE:-standard}
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

    # Display configuration
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

    # STEP 2: Request sudo privileges
    print_step "1/6" "Requesting Administrator Privileges"

    # Check if passwordless sudo is configured
    if sudo -n true 2>/dev/null; then
        log "Passwordless sudo is configured"
    else
        # Request password for sudo
        sudo -v || { error "Authentication failed"; exit 1; }

        # Sudo refresh background process - refresh every 30 seconds to keep credentials alive
        # This is critical for long nix builds that can take 20-30 minutes
        ( while true; do sudo -n -v 2>/dev/null; sleep 30; done ) &
        SUDO_REFRESH_PID=$!
        trap "kill $SUDO_REFRESH_PID 2>/dev/null || true" EXIT
        log "Sudo credentials will be kept alive during installation"
    fi

    print_success "Administrator access granted"
    echo ""

    # STEP 3: Install Xcode CLI tools
    print_step "2/6" "Installing Xcode Command Line Tools"
    if [[ -z "$(command -v git)" ]]; then
        log "Installing Xcode Command Line Tools..."
        xcode-select --install &> /dev/null
        log "Waiting for installation to complete..."
        until xcode-select --print-path &> /dev/null; do sleep 5; done
    fi
    print_success "Xcode Command Line Tools ready"
    echo ""

    # STEP 4: Ensure Homebrew
    print_step "3/6" "Setting up Homebrew"
    ensure_homebrew || {
        error "Failed to set up Homebrew"
        exit 1
    }
    print_success "Homebrew ready"
    echo ""

    # STEP 5: Install or fix Nix
    print_step "4/6" "Installing Nix Package Manager"
    install_or_fix_nix || {
        error "Failed to install or fix Nix"
        exit 1
    }
    export PATH=$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$PATH
    print_success "Nix installed and configured"
    echo ""

    # STEP 6: Clone/update repository
    print_step "5/6" "Setting up Configuration Repository"
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

    # Create lib and bin directories if they don't exist
    mkdir -p "$REPO_DIR/lib" "$REPO_DIR/bin"

    print_success "Repository ready"
    echo ""

    # STEP 7: Generate machine configuration and build
    print_step "6/6" "Building and Activating System"
    cd "$REPO_DIR"

    # Generate config if config-builder exists
    if [ -f "$REPO_DIR/lib/config-builder.sh" ]; then
        source "$REPO_DIR/lib/config-builder.sh"
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

    # Build and activate
    log "Building system configuration (this may take 15-30 minutes)..."
    # Export USERNAME for flake.nix to read (with --impure flag)
    export USERNAME="$NIXOS_USERNAME"

    if ! command -v darwin-rebuild &>/dev/null; then
        log "Installing nix-darwin..."
        nix build --extra-experimental-features "nix-command flakes" --impure \
            ".#darwinConfigurations.$HOST_NAME.system"
        sudo mkdir -p /etc/nix-darwin /etc/static
        # Use sudo env to preserve USERNAME through sudo
        sudo env USERNAME="$NIXOS_USERNAME" PATH="$PATH" ./result/sw/bin/darwin-rebuild switch --flake ".#$HOST_NAME" --impure
    else
        log "Activating configuration..."
        # Use sudo env to preserve USERNAME through sudo
        sudo env USERNAME="$NIXOS_USERNAME" PATH="$PATH" darwin-rebuild switch --flake ".#$HOST_NAME" --impure
    fi

    echo ""
    print_success "Installation complete!"

    # Print final instructions
    echo ""
    print_header "🎉 Welcome to nix-me!"
    echo ""
    echo "  Your macOS system is now managed with Nix."
    echo ""
    echo "  ${GREEN}Next Steps:${NC}"
    echo "  1. Restart your terminal (or run: exec \$SHELL)"
    echo "  2. Run: ${CYAN}nix-me doctor${NC} (check system health)"
    echo "  3. Run: ${CYAN}nix-me customize${NC} (add more apps)"
    echo "  4. Run: ${CYAN}nix-me --help${NC} (see all commands)"
    echo ""
    echo "  ${YELLOW}Useful Commands:${NC}"
    echo "  • ${CYAN}nix-me add app <n>${NC}  - Search and add GUI apps"
    echo "  • ${CYAN}nix-me add tool <n>${NC} - Add CLI tools"
    echo "  • ${CYAN}nix-me setup${NC}           - Re-run setup wizard"
    echo "  • ${CYAN}nix-me switch${NC}          - Apply configuration changes"
    echo ""
    echo "  ${GREEN}Configuration:${NC}"
    echo "  📁 ${REPO_DIR}"
    echo ""
}

# Run main function
main "$@"
