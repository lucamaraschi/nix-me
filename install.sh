#!/bin/bash

# Installation script for Nix/nix-darwin configuration
# Usage: ./install.sh [hostname] [machine-type] [machine-name]

set -e

# Colors for better output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Function to detect virtual machine environment
detect_vm_environment() {
    # Check for common VM indicators
    if system_profiler SPHardwareDataType 2>/dev/null | grep -i "virtual\|parallels\|vmware\|virtualbox" > /dev/null; then
        echo "traditional-vm"
        return
    fi
    
    # Check for Apple Virtual Machine specifically (Apple Virtualization Framework)
    if system_profiler SPHardwareDataType 2>/dev/null | grep -i "Apple Virtual Machine" > /dev/null; then
        echo "apple-vm"
        return
    fi
    
    # Check for UTM which uses QEMU or Apple Virtualization Framework
    if ps aux | grep -i "UTM" | grep -v grep > /dev/null; then
        echo "utm-vm"
        return
    fi
    
    # Check for virtualization kernel flag
    if sysctl kern.hv_vmm_present 2>/dev/null | grep -q "1"; then
        echo "virtualized"
        return
    fi
    
    # Not a VM
    echo "physical"
}

# Detect environment
VM_TYPE=$(detect_vm_environment)
echo -e "${GREEN}Detected environment: ${VM_TYPE}${NC}"

# Default values with proper handling of command-line arguments
if [ -z "$1" ]; then
    if [ "$VM_TYPE" != "physical" ]; then
        # Use a fixed hostname for VMs to avoid hostname-related issues
        HOST_NAME="nix-darwin-vm"
        echo -e "${YELLOW}Using fixed hostname '$HOST_NAME' for VM environment${NC}"
    else
        HOST_NAME=$(hostname -s)
        echo -e "${GREEN}Using detected hostname: $HOST_NAME${NC}"
    fi
else
    HOST_NAME=$1
fi

MACHINE_TYPE=${2:-""}
MACHINE_NAME=${3:-"$HOST_NAME"}
NIXOS_USERNAME=${4:-$(whoami)}
REPO_URL=${5:-"https://github.com/lucamaraschi/nix-me.git"}
REPO_BRANCH=${6:-"main"}
REPO_DIR=${HOME}/.config/nixpkgs

# Make sure HOST environment variable is set correctly for nix-darwin
export HOST="$HOST_NAME"

# Auto-detect machine type if not provided
if [[ -z "$MACHINE_TYPE" ]]; then
    if [ "$VM_TYPE" != "physical" ]; then
        MACHINE_TYPE="vm"
        echo -e "${YELLOW}Setting machine type to 'vm' for virtual environment${NC}"
    elif [[ "$HOST_NAME" == *"macbook"* || "$HOST_NAME" == *"mba"* ]]; then
        MACHINE_TYPE="macbook"
    elif [[ "$HOST_NAME" == *"mini"* ]]; then
        MACHINE_TYPE="macmini"
    fi
    echo "Auto-detected machine type: $MACHINE_TYPE"
fi

# Print header
echo "======================================================================"
echo "   Nix System Configuration Installer"
echo "======================================================================"
echo "   Hostname: $HOST_NAME"
echo "   Machine Type: $MACHINE_TYPE"
echo "   Machine Name: $MACHINE_NAME"
echo "   Username: $NIXOS_USERNAME"
echo "   Environment: $VM_TYPE"
echo "======================================================================"
echo ""

# Request sudo privileges at the beginning
sudo -v || { echo "Authentication failed"; exit 1; }

# Start a background job to refresh sudo credentials every 60 seconds
( while true; do sudo -v; sleep 60; done ) &
SUDO_REFRESH_PID=$!

function cleanup() {
    # Kill the sudo refresh process when the script exits
    if [[ -n "$SUDO_REFRESH_PID" ]]; then
        kill "$SUDO_REFRESH_PID" >/dev/null 2>&1 || true
        echo "Done. Sudo refresh process killed."
    fi
}

# Register the cleanup function to run on exit
trap cleanup EXIT

function setup_darwin_based_host() {
    if [[ "$OSTYPE" != "darwin"* ]]; then
        echo "⛔ Please run this script on a macOS machine"
        exit 1
    fi
    
    echo "🔍 Checking system requirements..."
    
    # Install Xcode Command Line Tools if not already installed
    if [[ -z "$(command -v git)" ]]; then
        echo "🛠 Installing Xcode Command Line Tools"
        xcode-select --install &> /dev/null
        
        echo "⏳ Waiting for Xcode Command Line Tools installation to complete..."
        until xcode-select --print-path &> /dev/null; do
            sleep 5
        done
    else
        echo "✅ Xcode Command Line Tools already installed"
    fi
    
    # Install or update Homebrew (skip on VMs if specified)
    if [ "$VM_TYPE" != "physical" ] && [ "$SKIP_BREW_ON_VM" = "true" ]; then
        echo -e "${YELLOW}Skipping Homebrew installation in VM environment${NC}"
    else
        if [[ $(command -v brew) == "" ]]; then
            echo "🍺 Installing Homebrew"
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            
            echo "🔄 Configuring Homebrew environment"
            if [[ -f /opt/homebrew/bin/brew ]]; then
                # Apple Silicon Mac
                echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> $HOME/.zprofile
                eval "$(/opt/homebrew/bin/brew shellenv)"
                
                # Also add to current session
                export PATH="/opt/homebrew/bin:$PATH"
            else
                # Intel Mac
                echo 'eval "$(/usr/local/bin/brew shellenv)"' >> $HOME/.zprofile
                eval "$(/usr/local/bin/brew shellenv)"
                
                # Also add to current session
                export PATH="/usr/local/bin:$PATH"
            fi
        else
            echo "✅ Homebrew already installed"
            
            # Ensure Homebrew is in PATH for this session regardless
            if [[ -f /opt/homebrew/bin/brew ]]; then
                export PATH="/opt/homebrew/bin:$PATH"
                eval "$(/opt/homebrew/bin/brew shellenv)"
            elif [[ -f /usr/local/bin/brew ]]; then
                export PATH="/usr/local/bin:$PATH"
                eval "$(/usr/local/bin/brew shellenv)"
            fi
            
            echo "🔄 Updating Homebrew"
            brew update
        fi
        
        # Verify Homebrew is in PATH
        if ! command -v brew &>/dev/null; then
            echo "⚠️ Warning: Homebrew installation appears successful but 'brew' command not found in PATH"
            echo "Adding Homebrew to PATH for this session..."
            
            if [[ -f /opt/homebrew/bin/brew ]]; then
                export PATH="/opt/homebrew/bin:$PATH"
            elif [[ -f /usr/local/bin/brew ]]; then
                export PATH="/usr/local/bin:$PATH"
            fi
            
            # Verify again
            if ! command -v brew &>/dev/null; then
                echo "⛔ Error: Unable to find 'brew' command. Installation may have failed."
                exit 1
            fi
        fi
    fi
    
    # Install Nix if not already installed
    # Check if Nix installation and daemon status
    if ! command -v nix &> /dev/null; then
        echo "📦 Nix is not installed. Installing Nix..."
        curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
        
        # Source Nix environment
        if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
            . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
        fi
    else
        echo "✅ Nix is already installed."
        
        # Check if nix-daemon is running
        if ! pgrep -x "nix-daemon" &> /dev/null; then
            echo "🔄 Nix daemon is not running. Starting nix-daemon..."
            
            # Check if we can run a simple nix command
            if ! nix-instantiate --eval -E 'builtins.currentTime' &> /dev/null; then
                # Try the most common methods to start the daemon
                if [ -e "/Library/LaunchDaemons/org.nixos.nix-daemon.plist" ]; then
                    echo "Starting nix-daemon via launchctl..."
                    sudo launchctl load /Library/LaunchDaemons/org.nixos.nix-daemon.plist
                elif [ -e "/nix/var/nix/profiles/default/etc/systemd/system/nix-daemon.service" ]; then
                    echo "Starting nix-daemon via systemd..."
                    sudo systemctl start nix-daemon
                elif [ -e "/nix/var/nix/profiles/default/etc/init.d/nix-daemon" ]; then
                    echo "Starting nix-daemon via init.d..."
                    sudo /nix/var/nix/profiles/default/etc/init.d/nix-daemon start
                else
                    # Last resort: Try to find the daemon binary and run it directly
                    NIX_DAEMON_PATH=$(find /nix -name "nix-daemon" -type f -executable 2>/dev/null | head -n1)
                    if [ -n "$NIX_DAEMON_PATH" ]; then
                        echo "Starting nix-daemon directly from $NIX_DAEMON_PATH..."
                        sudo "$NIX_DAEMON_PATH" &
                        sleep 2
                    else
                        echo "⚠️ Could not find nix-daemon binary."
                        echo "Please start the Nix daemon manually and run this script again."
                        echo "You may need to restart your computer for changes to take effect."
                        exit 1
                    fi
                fi
            else
                echo "Nix commands are working, proceeding without explicitly starting the daemon."
            fi
            
            # Verify daemon is working
            sleep 2
            if nix-instantiate --eval -E 'builtins.currentTime' &> /dev/null; then
                echo "✅ Nix daemon is functioning correctly."
            else
                echo "⛔ Nix daemon doesn't appear to be working properly."
                echo "You may need to restart your computer for changes to take effect."
                echo "Attempting to continue anyway..."
            fi
        else
            echo "✅ Nix daemon is already running."
        fi
    fi
    
    # Make sure PATH includes the Nix directories
    export PATH=$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$PATH
    
    # Back up existing Nix configuration
    if [ -f "/etc/nix/nix.conf" ] && [ ! -f "/etc/nix/nix.conf.before-nix-darwin" ]; then
        echo "📥 Backing up existing Nix configuration"
        sudo cp /etc/nix/nix.conf /etc/nix/nix.conf.before-nix-darwin
    fi
    
    # Back up existing zshenv if it exists
    if [ -f "/etc/zshenv" ] && [ ! -f "/etc/zshenv.before-nix-darwin" ]; then
        echo "📥 Backing up existing zshenv"
        sudo cp /etc/zshenv /etc/zshenv.before-nix-darwin
    fi
    
    # Clone or update the repository
    if [ -d "$REPO_DIR" ]; then
        echo "🔄 Updating existing repository"
        cd "$REPO_DIR"
        git fetch
        git checkout "$REPO_BRANCH"
        git pull
    else
        echo "📥 Cloning configuration repository $REPO_URL"
        mkdir -p "$REPO_DIR"
        git clone "$REPO_URL" "$REPO_DIR"
        cd "$REPO_DIR"
        git checkout "$REPO_BRANCH"
    fi
    
    # Create VM-specific configuration if in a VM environment
    if [ "$VM_TYPE" != "physical" ]; then
        echo -e "${YELLOW}Creating VM-friendly configuration override...${NC}"
        
        # Create a temporary configuration file for VMs
        cat > "$REPO_DIR/vm-overrides.nix" <<EOL
{ lib, ... }:
{
  # Disable Nix management (let Determinate handle it)
  nix.enable = false;
  
  # Disable dependent features
  nix.optimise.automatic = false;
  nix.gc.automatic = false;
  
  # Disable problematic Universal Access settings
  system.defaults.universalaccess.reduceMotion = lib.mkForce null;
  system.defaults.universalaccess.reduceTransparency = lib.mkForce null;
  system.defaults.universalaccess.mouseDriverCursorSize = lib.mkForce null;
  
  # Add any additional VM-specific settings here
}
EOL

        echo -e "${YELLOW}Note: For Universal Access settings to work, you may need to manually grant Terminal 'Full Disk Access' in System Preferences > Security & Privacy > Privacy.${NC}"
    fi
    
    # Install nix-darwin using the flake directly
    if ! command -v darwin-rebuild &> /dev/null; then
        echo "🛠 Installing nix-darwin via flake"
        
        # Ensure flakes are enabled
        mkdir -p ~/.config/nix
        echo "experimental-features = nix-command flakes" > ~/.config/nix/nix.conf
        
        # Use your existing flake to bootstrap nix-darwin
        cd "$REPO_DIR"
        
        # Build with VM-specific settings if in a VM environment
        if [ "$VM_TYPE" != "physical" ]; then
            echo -e "${GREEN}Building nix-darwin configuration for VM environment...${NC}"
            nix build --extra-experimental-features "nix-command flakes" \
                -I nixpkgs-overlays=$HOME/.config/nixpkgs/overlays \
                -I vm-overrides=$HOME/.config/nixpkgs/vm-overrides.nix \
                ".#darwinConfigurations.$HOST_NAME.system"
        else
            nix build .#darwinConfigurations."$HOST_NAME".system
        fi
        
        echo "HOST_NAME: $HOST_NAME"
        
        # Create necessary directories
        sudo mkdir -p /etc/nix-darwin /etc/static
        
        # Activate the system
        sudo ./result/sw/bin/darwin-rebuild switch --flake ".#$HOST_NAME"
    else
        echo "✅ nix-darwin already installed"
    fi
    
    # Build and activate configuration
    echo "🚀 Building your configuration..."
    cd "$REPO_DIR"
    
    # Source nix environment if it's not already sourced
    if ! command -v nix &>/dev/null; then
        if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
            . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
        fi
    fi
    
    # Source darwin environment if it's not already sourced
    if ! command -v darwin-rebuild &>/dev/null; then
        PATH=$HOME/.nix-profile/bin:$PATH
        if [ -e /etc/static/bashrc ]; then
            . /etc/static/bashrc
        fi
    fi
    
    echo "🚀 Activating your configuration..."
    # Use the Makefile from the repository
    if [ -f "$REPO_DIR/Makefile" ]; then
        sudo make HOSTNAME="$HOST_NAME" MACHINE_TYPE="$MACHINE_TYPE" MACHINE_NAME="$MACHINE_NAME" switch
    else
        # Fallback in case the Makefile is missing for some reason
        echo "⚠️ Warning: Makefile not found in the repository. Using direct command."
        if [ "$VM_TYPE" != "physical" ]; then
            # Use VM-specific settings for the activation
            sudo HOSTNAME="$HOST_NAME" MACHINE_TYPE="$MACHINE_TYPE" MACHINE_NAME="$MACHINE_NAME" \
                darwin-rebuild switch \
                -I vm-overrides=$HOME/.config/nixpkgs/vm-overrides.nix \
                --flake "$REPO_DIR"
        else
            sudo HOSTNAME="$HOST_NAME" MACHINE_TYPE="$MACHINE_TYPE" MACHINE_NAME="$MACHINE_NAME" \
                darwin-rebuild switch --flake "$REPO_DIR"
        fi
    fi
    
    echo "✅ Installation completed successfully!"
    echo "🔧 You may need to restart your terminal or computer to apply all changes."
}

# Run the installation
setup_darwin_based_host

# Print final instructions
echo ""
echo "======================================================================"
echo "   Installation Complete!"
echo "======================================================================"
echo "   Your Nix system is now set up according to your configuration."
echo ""
echo "   Next steps:"
echo "   1. Restart your terminal or run 'source /etc/bashrc'"
echo "   2. Customize your configuration in $REPO_DIR"
echo "   3. Apply changes with 'make switch'"
echo "======================================================================"