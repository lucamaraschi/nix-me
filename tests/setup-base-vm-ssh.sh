#!/bin/bash

# Automated SSH-based Base VM Setup for nix-me Testing
# This script connects to a VM via SSH and prepares it as a base VM

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
UTMCTL="/Applications/UTM.app/Contents/MacOS/utmctl"
VM_NAME=""
VM_USER=""
VM_IP=""
SSH_KEY=""
DISABLE_SSH_AFTER=false
SHUTDOWN_AFTER=true
START_VM=true

# Logging
log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING:${NC} $1"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR:${NC} $1"; }
info() { echo -e "${BLUE}[$(date '+%H:%M:%S')] INFO:${NC} $1"; }
step() { echo -e "${CYAN}[$1]${NC} $2"; }

usage() {
    cat << EOF
Usage: $0 --vm=NAME --user=USERNAME [OPTIONS]

Automated SSH-based setup for nix-me base VM

REQUIRED:
    --vm=NAME               Name of the VM to set up
    --user=USERNAME         SSH username for the VM

OPTIONS:
    --ip=IP_ADDRESS         VM IP address (auto-detected if not specified)
    --ssh-key=PATH          Path to SSH key (uses default if not specified)
    --disable-ssh           Disable SSH after setup (more secure)
    --no-shutdown           Don't shutdown VM after setup
    --no-start              Don't start VM (assumes it's already running)
    -h, --help              Show this help message

PREREQUISITES:
    1. VM must have Remote Login (SSH) enabled:
       System Settings → General → Sharing → Remote Login
    2. VM must be on same network as host (Shared Network in UTM)
    3. User must have sudo access in the VM

EXAMPLES:
    $0 --vm="macOS Tahoe - base" --user=admin
    $0 --vm="My VM" --user=testuser --disable-ssh
    $0 --vm="Clean VM" --user=admin --ip=192.168.64.5 --no-shutdown

WHAT IT DOES:
    1. Starts the VM (if needed)
    2. Connects via SSH
    3. Configures system settings (disables sleep, screensaver, updates)
    4. Optionally disables SSH
    5. Optionally shuts down VM

NOTE: Does NOT install Homebrew or guest agent - keeps VM truly clean
      to test the complete installation flow

EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --vm=*)
            VM_NAME="${1#*=}"
            shift
            ;;
        --user=*)
            VM_USER="${1#*=}"
            shift
            ;;
        --ip=*)
            VM_IP="${1#*=}"
            shift
            ;;
        --ssh-key=*)
            SSH_KEY="${1#*=}"
            shift
            ;;
        --disable-ssh)
            DISABLE_SSH_AFTER=true
            shift
            ;;
        --no-shutdown)
            SHUTDOWN_AFTER=false
            shift
            ;;
        --no-start)
            START_VM=false
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            error "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate required parameters
if [ -z "$VM_NAME" ] || [ -z "$VM_USER" ]; then
    error "Required parameters missing"
    usage
fi

# Check if UTM is installed
if [ ! -f "$UTMCTL" ]; then
    error "UTM not found. Please install UTM from https://mac.getutm.app/"
    exit 1
fi

# Check if VM exists
if ! $UTMCTL list | grep -q "$VM_NAME"; then
    error "VM '$VM_NAME' not found"
    info "Available VMs:"
    $UTMCTL list
    exit 1
fi

# SSH options
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"
if [ -n "$SSH_KEY" ]; then
    SSH_OPTS="$SSH_OPTS -i $SSH_KEY"
fi

# Main setup flow
main() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  Automated Base VM Setup                  ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════╝${NC}"
    echo ""

    info "VM Name: $VM_NAME"
    info "User: $VM_USER"
    echo ""

    # Step 1: Start VM if needed
    if [ "$START_VM" = "true" ]; then
        step "1/7" "Starting VM"

        local status=$($UTMCTL status "$VM_NAME" | grep -o "started\|stopped" || echo "unknown")

        if [ "$status" = "stopped" ]; then
            log "Starting VM: $VM_NAME"
            $UTMCTL start "$VM_NAME" --hide
            sleep 5
            log "VM started"
        else
            log "VM already running"
        fi
    else
        step "1/7" "VM already running (--no-start)"
    fi

    # Step 2: Get VM IP if not provided
    step "2/7" "Getting VM IP address"

    if [ -z "$VM_IP" ]; then
        log "Auto-detecting VM IP..."

        # Wait for guest agent and IP
        local attempts=0
        while [ $attempts -lt 30 ]; do
            VM_IP=$($UTMCTL ip-address "$VM_NAME" 2>/dev/null | head -1)

            if [ -n "$VM_IP" ] && [ "$VM_IP" != "unknown" ]; then
                log "Detected IP: $VM_IP"
                break
            fi

            sleep 2
            attempts=$((attempts + 1))
        done

        if [ -z "$VM_IP" ] || [ "$VM_IP" = "unknown" ]; then
            error "Could not detect VM IP address"
            warn "Make sure:"
            warn "  1. VM has network connectivity"
            warn "  2. Guest agent is installed (or use --ip to specify manually)"
            exit 1
        fi
    else
        log "Using provided IP: $VM_IP"
    fi

    # Step 3: Test SSH connectivity
    step "3/7" "Testing SSH connectivity"

    log "Testing SSH to $VM_USER@$VM_IP..."

    if ! ssh $SSH_OPTS "$VM_USER@$VM_IP" "echo 'SSH test successful'" 2>/dev/null; then
        error "SSH connection failed"
        warn "Please ensure:"
        warn "  1. Remote Login is enabled in VM"
        warn "  2. User can connect: ssh $VM_USER@$VM_IP"
        warn "  3. SSH keys are set up or password auth is enabled"
        exit 1
    fi

    log "SSH connection successful"

    # Step 4: Configure system settings
    step "4/5" "Configuring system settings"

    log "Applying system configurations..."

    ssh $SSH_OPTS "$VM_USER@$VM_IP" << 'ENDSSH'
set -e

echo "Disabling screen saver..."
defaults -currentHost write com.apple.screensaver idleTime 0

echo "Disabling sleep..."
sudo pmset -a sleep 0
sudo pmset -a displaysleep 0

echo "Disabling automatic updates..."
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled -bool false

echo "System configuration complete"
ENDSSH

    log "System settings configured"

    # Step 5: Optional SSH disable and shutdown
    step "5/5" "Finalizing setup"

    if [ "$DISABLE_SSH_AFTER" = "true" ]; then
        log "Disabling Remote Login (SSH)..."

        ssh $SSH_OPTS "$VM_USER@$VM_IP" << 'ENDSSH'
sudo systemsetup -setremotelogin off
echo "Remote Login disabled"
ENDSSH

        log "SSH disabled for security"
    fi

    if [ "$SHUTDOWN_AFTER" = "true" ]; then
        log "Shutting down VM..."

        ssh $SSH_OPTS "$VM_USER@$VM_IP" "sudo shutdown -h now" || true
        sleep 2

        # Wait for VM to stop
        local attempts=0
        while [ $attempts -lt 30 ]; do
            local status=$($UTMCTL status "$VM_NAME" 2>/dev/null | grep -o "started\|stopped" || echo "unknown")
            if [ "$status" = "stopped" ]; then
                break
            fi
            sleep 2
            attempts=$((attempts + 1))
        done

        log "VM shut down"
    else
        log "VM left running (--no-shutdown)"
    fi

    # Final summary
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  Setup Complete!                           ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════╝${NC}"
    echo ""
    echo "  VM Name:          $VM_NAME"
    echo "  Status:           Ready for testing"
    echo ""
    echo -e "${GREEN}Configured:${NC}"
    echo "  ✓ System settings (sleep, screensaver, updates disabled)"
    echo "  ✓ SSH enabled for testing"
    echo ""
    echo -e "${GREEN}What's kept clean:${NC}"
    echo "  • NO Homebrew (installed during test)"
    echo "  • NO guest agent (not needed for SSH-based testing)"
    echo "  • Truly clean macOS for complete installation testing"
    echo ""
    echo -e "${GREEN}Next steps:${NC}"
    echo "  1. VM is ready as a clean base for testing"
    echo "  2. Run tests with: ${CYAN}./tests/vm-test.sh --base-vm=\"$VM_NAME\" --vm-user=$VM_USER${NC}"
    echo ""

    if [ "$DISABLE_SSH_AFTER" != "true" ]; then
        warn "SSH is still enabled in the VM"
        info "To disable for security: System Settings → Sharing → Remote Login"
    fi

    log "Base VM setup completed successfully!"
}

# Run main
main
