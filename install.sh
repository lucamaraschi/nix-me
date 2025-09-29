#!/bin/bash

# Installation script for Nix/nix-darwin configuration
# Usage: ./install.sh [hostname] [machine-type] [machine-name]
# Environment variables:
#   FORCE_NIX_REINSTALL=1    Force complete Nix reinstall
#   NON_INTERACTIVE=1        Skip confirmation prompts
#   SKIP_BREW_ON_VM=1        Skip Homebrew installation in VMs

set -e

# Colors for better output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
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

    # Test 5: Can actually build something simple (but only if store seems healthy)
    # Skip this test on fresh installations - it's too aggressive
    if [ -d "/nix/store" ] && [ "$(ls -A /nix/store 2>/dev/null | wc -l)" -gt 10 ]; then
        # Store has some packages, safe to test building
        if ! timeout 30 nix-build '<nixpkgs>' -A hello --no-out-link &>/dev/null 2>&1; then
            warn "Nix cannot build packages, but continuing anyway (might be fresh install)"
            # Don't fail on this - just warn
        fi
    else
        log "Skipping build test on fresh/minimal Nix store"
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
    elif [ -f /nix/receipt.json ]; then
        warn "Found Determinate Systems installation but uninstaller missing"
        log "Attempting to download and use uninstaller"

        # Try to download the uninstaller that matches the installation
        if curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix --output /tmp/nix-installer.sh; then
            chmod +x /tmp/nix-installer.sh
            sudo /tmp/nix-installer.sh uninstall || warn "Downloaded uninstaller failed"
            rm -f /tmp/nix-installer.sh
        fi
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

    # Remove shell modifications
    sudo rm -f /etc/bashrc.backup-before-nix
    sudo rm -f /etc/zshrc.backup-before-nix
    sudo rm -f /etc/bash.bashrc.backup-before-nix

    # Remove synthetic.conf entries (Determinate Systems specific)
    if [ -f /etc/synthetic.conf ]; then
        sudo sed -i.backup '/^nix$/d' /etc/synthetic.conf 2>/dev/null || true
    fi

    # Remove fstab entries (Determinate Systems specific)
    if [ -f /etc/fstab ]; then
        sudo sed -i.backup '/nix/d' /etc/fstab 2>/dev/null || true
    fi

    # Remove user-level Nix
    rm -rf ~/.nix-* 2>/dev/null || true
    rm -rf ~/.config/nix 2>/dev/null || true
    rm -rf ~/.cache/nix 2>/dev/null || true

    # Remove from PATH in current session
    export PATH=$(echo "$PATH" | sed -e 's|/nix/var/nix/profiles/default/bin:||g' -e 's|'"$HOME"'/.nix-profile/bin:||g')

    # Remove nix users and group (Determinate Systems creates these)
    for i in $(seq 1 32); do
        sudo dscl . -delete /Users/_nixbld$i 2>/dev/null || true
    done
    sudo dscl . -delete /Groups/nixbld 2>/dev/null || true

    # Verify cleanup
    if command -v nix &>/dev/null; then
        error "Nix uninstall incomplete - nix command still available"
        error "You may need to restart your computer and try again"
        return 1
    fi

    if [ -f /nix/receipt.json ]; then
        error "Nix uninstall incomplete - receipt.json still exists"
        error "This will cause 'existing plan' errors on reinstall"
        return 1
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

    # Check if we have unpushed commits
    if [ "$(git rev-list HEAD...origin/$repo_branch --count 2>/dev/null || echo 0)" -gt 0 ]; then
        warn "Local commits detected that aren't on remote"
        log "Creating backup branch..."
        git branch "backup-$(date +%Y%m%d-%H%M%S)" HEAD || true
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
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

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
                echo -e "${YELLOW}Nix installation appears broken. Reinstall? (y/N)${NC}"
                read -r response
                case "$response" in
                    [yY][eE][sS]|[yY])
                        log "User confirmed reinstall"
                        ;;
                    *)
                        error "User declined reinstall. Cannot continue."
                        error "To force reinstall, run: FORCE_NIX_REINSTALL=1 $0"
                        return 1
                        ;;
                esac
            fi

            # Uninstall broken Nix
            uninstall_nix || return 1
        fi
    fi

    # Install fresh Nix
    log "Installing Nix using Determinate Systems installer..."

    # Check for existing receipt that would cause "existing plan" error
    if [ -f /nix/receipt.json ]; then
        warn "Found existing Nix installation receipt"
        log "Removing receipt to prevent 'existing plan' error..."
        sudo rm -f /nix/receipt.json || {
            error "Could not remove existing receipt.json"
            error "Please run: sudo rm -f /nix/receipt.json"
            return 1
        }
    fi

    curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install

    # Source environment
    if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
        source '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
    fi

    # Update PATH for current session
    export PATH=$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$PATH

    # Test the new installation with a more lenient test for fresh installs
    log "Verifying fresh Nix installation..."

    # Give the daemon a moment to fully start
    sleep 3

    # Basic functionality test (more lenient for fresh installs)
    if command -v nix &>/dev/null && nix --version &>/dev/null && nix-instantiate --eval -E '1 + 1' &>/dev/null; then
        log "Nix installation completed successfully"
        log "Note: Full functionality will be available after first package download"
        return 0
    else
        error "Nix installation failed basic verification"
        error "Please check the installation logs and try again"
        return 1
    fi
}

# Function to detect virtual machine environment
detect_vm_environment() {
    # Method 1: Check system profiler for actual VM hardware first
    local hardware_info=$(system_profiler SPHardwareDataType 2>/dev/null)

    # Check for explicit VM indicators in hardware
    if echo "$hardware_info" | grep -i "virtual\|parallels\|vmware\|virtualbox" > /dev/null; then
        echo "traditional-vm"
        return
    fi

    # Check for Apple Virtual Machine specifically (actual VM hardware)
    if echo "$hardware_info" | grep -i "Apple Virtual Machine" > /dev/null; then
        echo "apple-vm"
        return
    fi

    # Method 2: Check for virtualization kernel flag (actual running in VM)
    if sysctl kern.hv_vmm_present 2>/dev/null | grep -q "1"; then
        # Additional check: make sure we're actually IN a VM, not just capable of running VMs
        if sysctl kern.hv_support 2>/dev/null | grep -q "1"; then
            echo "virtualized"
            return
        fi
    fi

    # Method 3: Check hardware model for VM indicators
    local model=$(sysctl -n hw.model 2>/dev/null)
    if echo "$model" | grep -i "virtual" > /dev/null; then
        echo "vm-hardware"
        return
    fi

    # Method 4: Check for VM-specific devices (last resort)
    if ioreg -l | grep -i "vmware\|parallels\|virtualbox\|qemu" > /dev/null 2>&1; then
        echo "vm-devices"
        return
    fi

    # If we get here, it's a physical machine
    # Note: UTM app being installed/running does NOT mean we're in a VM
    echo "physical"
}

# Main installation function
main() {
    # Allow environment variables to control behavior
    FORCE_NIX_REINSTALL=${FORCE_NIX_REINSTALL:-0}
    NON_INTERACTIVE=${NON_INTERACTIVE:-0}
    SKIP_BREW_ON_VM=${SKIP_BREW_ON_VM:-0}

    # Detect environment
    VM_TYPE=$(detect_vm_environment)
    log "Detected environment: ${VM_TYPE}"

    # Handle command-line arguments with better defaults
    if [ -z "$1" ]; then
        if [ "$VM_TYPE" != "physical" ]; then
            HOST_NAME="nix-darwin-vm"
            log "Using fixed hostname '$HOST_NAME' for VM environment"
        else
            HOST_NAME=$(hostname -s)
            log "Using detected hostname: $HOST_NAME"
        fi
    else
        HOST_NAME=$1
    fi

    MACHINE_TYPE=${2:-""}
    MACHINE_NAME=${3:-"$HOST_NAME"}
    NIXOS_USERNAME=${4:-$(whoami)}
    REPO_URL=${5:-"https://github.com/lucamaraschi/nix-me.git"}
    REPO_BRANCH=${6:-${REPO_BRANCH:-"main"}}
    REPO_DIR=${HOME}/.config/nixpkgs

    # Auto-detect machine type if not provided
    if [[ -z "$MACHINE_TYPE" ]]; then
        if [ "$VM_TYPE" != "physical" ]; then
            MACHINE_TYPE="vm"
            log "Setting machine type to 'vm' for virtual environment"
        elif [[ "$HOST_NAME" == *"macbook"* || "$HOST_NAME" == *"mba"* ]]; then
            MACHINE_TYPE="macbook"
        elif [[ "$HOST_NAME" == *"mini"* ]]; then
            MACHINE_TYPE="macmini"
        fi
        log "Auto-detected machine type: $MACHINE_TYPE"
    fi

    # Set HOST environment variable
    export HOST="$HOST_NAME"

    # Print configuration summary
    echo "======================================================================"
    echo "   Nix System Configuration Installer"
    echo "======================================================================"
    echo "   Hostname: $HOST_NAME"
    echo "   Machine Type: $MACHINE_TYPE"
    echo "   Machine Name: $MACHINE_NAME"
    echo "   Username: $NIXOS_USERNAME"
    echo "   Environment: $VM_TYPE"
    echo "   Repository: $REPO_URL"
    echo "   Branch: $REPO_BRANCH"
    echo "   Force Nix Reinstall: $FORCE_NIX_REINSTALL"
    echo "   Non-Interactive: $NON_INTERACTIVE"
    echo "======================================================================"
    echo ""

    # Verify we're on macOS
    if [[ "$OSTYPE" != "darwin"* ]]; then
        error "This script must be run on macOS"
        exit 1
    fi

    # Request sudo privileges at the beginning
    log "Requesting administrator privileges..."
    sudo -v || { error "Authentication failed"; exit 1; }

    # Start background sudo refresh
    ( while true; do sudo -v; sleep 60; done ) &
    SUDO_REFRESH_PID=$!

    # Cleanup function
    cleanup() {
        if [[ -n "$SUDO_REFRESH_PID" ]]; then
            kill "$SUDO_REFRESH_PID" >/dev/null 2>&1 || true
        fi
    }
    trap cleanup EXIT

    # Install Xcode Command Line Tools if needed
    if [[ -z "$(command -v git)" ]]; then
        log "Installing Xcode Command Line Tools"
        xcode-select --install &> /dev/null

        log "Waiting for Xcode Command Line Tools installation..."
        until xcode-select --print-path &> /dev/null; do
            sleep 5
        done
    else
        log "Xcode Command Line Tools already installed"
    fi

    # Ensure Homebrew is properly set up
    ensure_homebrew || {
        error "Failed to set up Homebrew"
        exit 1
    }

    # Install or fix Nix
    install_or_fix_nix || {
        error "Failed to install or fix Nix"
        exit 1
    }

    # Make sure PATH includes Nix directories
    export PATH=$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$PATH

    # Clone or update repository safely
    if [ -d "$REPO_DIR" ]; then
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

    # Create VM-specific configuration if needed
    if [ "$VM_TYPE" != "physical" ]; then
        log "Creating VM-friendly configuration override for $VM_TYPE environment..."
        cat > "$REPO_DIR/vm-overrides.nix" <<EOL
{ lib, ... }:
{
  # VM-specific optimizations
  nix.optimise.automatic = lib.mkForce false;
  nix.gc.automatic = lib.mkForce false;

  # Disable Universal Access settings that might fail in VMs
  system.defaults.universalaccess = lib.mkForce {};

  # VM-optimized settings
  system.defaults.dock.tilesize = lib.mkForce 24; # Smaller for VM resolution

  # Disable problematic activation scripts for VMs
  system.activationScripts.extraActivation.text = lib.mkForce "";
}
EOL
    fi

    # Build and activate configuration
    cd "$REPO_DIR"

    # Ensure flakes are enabled
    mkdir -p ~/.config/nix
    echo "experimental-features = nix-command flakes" > ~/.config/nix/nix.conf

    # Install nix-darwin if not already installed
    if ! command -v darwin-rebuild &> /dev/null; then
        log "Installing nix-darwin via flake..."

        if [ "$VM_TYPE" != "physical" ]; then
            log "Building configuration for VM environment..."
            nix build --extra-experimental-features "nix-command flakes" \
                ".#darwinConfigurations.$HOST_NAME.system"
        else
            nix build ".#darwinConfigurations.$HOST_NAME.system"
        fi

        # Create necessary directories and activate
        sudo mkdir -p /etc/nix-darwin /etc/static
        sudo ./result/sw/bin/darwin-rebuild switch --flake ".#$HOST_NAME"
    else
        log "nix-darwin already installed"
    fi

    # Apply configuration using Makefile
    log "Applying configuration..."
    if [ -f "$REPO_DIR/Makefile" ]; then
        sudo make HOSTNAME="$HOST_NAME" MACHINE_TYPE="$MACHINE_TYPE" MACHINE_NAME="$MACHINE_NAME" switch
    else
        warn "Makefile not found, using direct command"
        sudo HOSTNAME="$HOST_NAME" MACHINE_TYPE="$MACHINE_TYPE" MACHINE_NAME="$MACHINE_NAME" \
            darwin-rebuild switch --flake "$REPO_DIR"
    fi

    log "Installation completed successfully!"
    log "You may need to restart your terminal or computer to apply all changes."

    # Print final instructions
    echo ""
    echo "======================================================================"
    echo "   Installation Complete!"
    echo "======================================================================"
    echo "   Your Nix system is now configured for $MACHINE_TYPE use."
    echo ""
    echo "   Next steps:"
    echo "   1. Restart your terminal or run 'source /etc/bashrc'"
    echo "   2. Customize your configuration in $REPO_DIR"
    echo "   3. Apply changes with 'make switch'"
    echo "   4. Check status with 'make check'"
    echo ""
    echo "   Troubleshooting:"
    echo "   - Force Nix reinstall: FORCE_NIX_REINSTALL=1 $0"
    echo "   - Non-interactive mode: NON_INTERACTIVE=1 $0"
    echo "   - Skip Homebrew on VM: SKIP_BREW_ON_VM=1 $0"
    echo "======================================================================"
}

# Run main function with all arguments
main "$@"
