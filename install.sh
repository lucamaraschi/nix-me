#!/bin/bash

# Standalone installation script for Nix configuration
# Run with: curl -L https://your-host.com/install.sh | bash

set -e

# Default values
HOST_NAME=$(hostname -s)
MACHINE_TYPE=""
MACHINE_NAME="$HOST_NAME"
NIXOS_USERNAME=$(whoami)
REPO_URL="https://github.com/lucamaraschi/nix-me.git"
REPO_BRANCH="main"
REPO_DIR="$HOME/.config/nixpkgs"

# Print header
echo "======================================================================"
echo "   Nix System Configuration Installer"
echo "======================================================================"
echo "   Hostname: $HOST_NAME"
echo "   Machine Type: $MACHINE_TYPE"
echo "   Machine Name: $MACHINE_NAME"
echo "   Username: $NIXOS_USERNAME"
echo "   Repository: $REPO_URL"
echo "   Branch: $REPO_BRANCH"
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
    
    # Install or update Homebrew
    if [[ $(command -v brew) == "" ]]; then
        echo "🍺 Installing Homebrew"
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        
        echo "🔄 Configuring Homebrew environment"
        if [[ -f /opt/homebrew/bin/brew ]]; then
            # Apple Silicon Mac
            (echo; echo 'eval "$(/opt/homebrew/bin/brew shellenv)"') >> $HOME/.zprofile
            eval "$(/opt/homebrew/bin/brew shellenv)"
        else
            # Intel Mac
            (echo; echo 'eval "$(/usr/local/bin/brew shellenv)"') >> $HOME/.zprofile
            eval "$(/usr/local/bin/brew shellenv)"
        fi
    else
        echo "✅ Homebrew already installed"
        echo "🔄 Updating Homebrew"
        brew update
    fi
    
    # Install Nix if not already installed
    if [[ $(command -v nix) == "" ]]; then
        echo "📦 Installing Nix"
        curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
        
        # Source Nix environment
        if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
            . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
        fi
        
        # Configure Nix
        mkdir -p $HOME/.config/nix
        echo "experimental-features = nix-command flakes" > $HOME/.config/nix/nix.conf
    else
        echo "✅ Nix already installed"
    fi
    
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
        echo "📥 Cloning configuration repository"
        mkdir -p "$REPO_DIR"
        git clone "$REPO_URL" "$REPO_DIR"
        cd "$REPO_DIR"
        git checkout "$REPO_BRANCH"
    fi
    
    # Install nix-darwin
    if ! command -v darwin-rebuild &> /dev/null; then
        echo "🛠 Installing nix-darwin"
        nix-build https://github.com/LnL7/nix-darwin/archive/master.tar.gz -A installer
        ./result/bin/darwin-installer
        
        # Source darwin environment (if installer didn't do it already)
        if [ -e "$HOME/.nix-profile/etc/profile.d/nix-darwin.sh" ]; then
            . "$HOME/.nix-profile/etc/profile.d/nix-darwin.sh"
        fi
    else
        echo "✅ nix-darwin already installed"
    fi
    
    # Build and activate configuration
    echo "🚀 Building and activating your configuration..."
    cd "$REPO_DIR"
    
    # Auto-detect machine type if not specified
    if [[ -z "$MACHINE_TYPE" ]]; then
        if [[ "$HOST_NAME" == *"macbook"* || "$HOST_NAME" == *"mba"* ]]; then
            MACHINE_TYPE="macbook"
        elif [[ "$HOST_NAME" == *"mini"* ]]; then
            MACHINE_TYPE="macmini"
        fi
    fi
    
    # Run the build
    HOSTNAME="$HOST_NAME" MACHINE_TYPE="$MACHINE_TYPE" MACHINE_NAME="$MACHINE_NAME" darwin-rebuild switch --flake .
    
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
echo "   3. Apply changes with 'cd $REPO_DIR && make switch'"
echo "======================================================================"