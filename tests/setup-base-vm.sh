#!/bin/bash

# Manual setup script to be run INSIDE the base VM
# For automated setup from the host, use: setup-base-vm-ssh.sh
#
# This script should be run INSIDE the base VM after macOS installation

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING:${NC} $1"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR:${NC} $1"; }
info() { echo -e "${BLUE}[$(date '+%H:%M:%S')] INFO:${NC} $1"; }
step() { echo -e "${CYAN}[$1]${NC} $2"; }

echo ""
echo -e "${CYAN}╔════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  nix-me Base VM Setup (Manual)             ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════╝${NC}"
echo ""

info "This script will configure this macOS VM for nix-me testing"
info "NOTE: For automated setup, use setup-base-vm-ssh.sh from the host"
echo ""

# Check if we're in a VM
if system_profiler SPHardwareDataType | grep -q "Apple Virtual Machine"; then
    log "✓ Running in a virtual machine"
else
    warn "This doesn't appear to be a virtual machine"
    read -p "Continue anyway? (y/N): " answer
    if [[ ! $answer =~ ^[Yy] ]]; then
        exit 0
    fi
fi

# Step 1: Install Homebrew
step "1/5" "Installing Homebrew"

if command -v brew &>/dev/null; then
    log "✓ Homebrew already installed"
else
    log "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Add to PATH
    if [ -f /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
    elif [ -f /usr/local/bin/brew ]; then
        eval "$(/usr/local/bin/brew shellenv)"
        echo 'eval "$(/usr/local/bin/brew shellenv)"' >> ~/.zprofile
    fi

    log "✓ Homebrew installed"
fi

# Step 2: Install QEMU (for guest agent)
step "2/5" "Installing QEMU Guest Agent"

if brew list qemu &>/dev/null; then
    log "✓ QEMU already installed"
else
    log "Installing QEMU..."
    brew install qemu
    log "✓ QEMU installed"
fi

# Enable guest agent
log "Starting QEMU guest agent..."
if brew services list | grep -q "qemu.*started"; then
    log "✓ Guest agent already running"
else
    brew services start qemu
    log "✓ Guest agent started"
fi

# Step 3: System Configuration
step "3/5" "Configuring system settings"

# Disable screen saver
log "Disabling screen saver..."
defaults -currentHost write com.apple.screensaver idleTime 0

# Disable sleep
log "Disabling sleep..."
sudo pmset -a sleep 0
sudo pmset -a displaysleep 0

# Disable software updates
log "Disabling automatic updates..."
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled -bool false

log "✓ System settings configured"

# Step 4: Network Test
step "4/5" "Testing network connectivity"

if ping -c 1 github.com &>/dev/null; then
    log "✓ Network connectivity OK"
else
    error "Network connectivity test failed"
    warn "Please check VM network settings"
fi

# Step 5: Cleanup
step "5/5" "Cleaning up"

log "Clearing download cache..."
rm -rf ~/Downloads/*

log "Clearing bash history..."
cat /dev/null > ~/.bash_history
cat /dev/null > ~/.zsh_history

log "✓ Cleanup complete"

# Final instructions
echo ""
echo -e "${CYAN}╔════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  Base VM Setup Complete!                   ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}Next steps:${NC}"
echo ""
echo "1. Shut down this VM (don't suspend)"
echo "   ${CYAN}sudo shutdown -h now${NC}"
echo ""
echo "2. In UTM, rename this VM to: ${YELLOW}macOS Tahoe - base${NC}"
echo ""
echo "3. Run the VM test script on your host:"
echo "   ${CYAN}./tests/vm-test.sh${NC}"
echo ""
echo -e "${YELLOW}Optional:${NC}"
echo "- Take a snapshot of this VM for quick restore"
echo "- Duplicate this VM as a backup"
echo ""

# Show summary
echo -e "${BLUE}Installed components:${NC}"
brew list | grep -E "^(qemu|homebrew)" || echo "- Homebrew"
echo ""

log "Base VM is ready for testing!"
