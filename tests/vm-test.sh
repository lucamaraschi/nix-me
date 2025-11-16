#!/bin/bash

# Automated VM Testing for nix-me
# This script creates an ephemeral UTM VM, installs nix-me, and runs tests

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
BASE_VM_NAME=""  # Will be set from flag or default
TEST_VM_NAME=""  # Will be set from flag or generated
VM_TIMEOUT=300  # 5 minutes for VM to start
INSTALL_TIMEOUT=1800  # 30 minutes for installation

# Flags
SOURCE="github"           # github | local
ON_SUCCESS="ask"          # ask | keep | delete
ON_FAILURE="keep"         # ask | keep | delete
VERBOSE=false
VM_USER=""                # SSH username for VM
VM_SSH_KEY=""             # SSH key path (optional)
VM_IP=""                  # VM IP address (optional, auto-detected if not provided)

# Logging functions
log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING:${NC} $1"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR:${NC} $1"; }
info() { echo -e "${BLUE}[$(date '+%H:%M:%S')] INFO:${NC} $1"; }
step() { echo -e "${CYAN}[$1]${NC} $2"; }

# Usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Automated VM testing for nix-me installation

OPTIONS:
    --base-vm=NAME          Name of the base VM to clone [default: macOS Tahoe - base]
    --name=NAME             Name for the test VM [default: nix-me-test-RANDOM]
    --vm-user=USERNAME      SSH username for VM (required for testing)
    --vm-ip=IP_ADDRESS      VM IP address (optional, auto-detected if not specified)
    --ssh-key=PATH          Path to SSH key (optional, uses default if not specified)
    --source=SOURCE         Source to test from: 'github' or 'local' [default: github]
    --onsuccess=ACTION      What to do if tests pass: 'keep', 'delete', or 'ask' [default: ask]
    --onfailure=ACTION      What to do if tests fail: 'keep', 'delete', or 'ask' [default: keep]
    --verbose               Show detailed output
    -h, --help              Show this help message

LEGACY OPTIONS (still supported):
    --local                 Same as --source=local
    --github                Same as --source=github
    --keep                  Keep VM regardless of result
    --delete                Delete VM regardless of result

EXAMPLES:
    $0 --vm-user=admin --vm-ip=192.168.64.5     # Provide VM IP (recommended)
    $0 --vm-user=admin --base-vm="My VM"        # Use different base VM
    $0 --vm-user=admin --name="test-1"          # Custom test VM name
    $0 --vm-user=admin --onsuccess=delete       # Auto-delete on success
    $0 --vm-user=admin --ssh-key=~/.ssh/id_rsa  # Use specific SSH key
    $0 --vm-user=admin --source=github          # Test from GitHub (default)
    $0 --vm-user=admin --source=local           # Test local changes via SCP

NOTE: Without guest agent in VM, you need to provide --vm-ip manually.
      Start the base VM first, get its IP from System Settings → Network,
      then use that IP with --vm-ip.

EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --base-vm=*)
            BASE_VM_NAME="${1#*=}"
            shift
            ;;
        --name=*)
            TEST_VM_NAME="${1#*=}"
            shift
            ;;
        --vm-user=*)
            VM_USER="${1#*=}"
            shift
            ;;
        --ssh-key=*)
            VM_SSH_KEY="${1#*=}"
            shift
            ;;
        --vm-ip=*)
            VM_IP="${1#*=}"
            shift
            ;;
        --source=*)
            SOURCE="${1#*=}"
            if [[ ! "$SOURCE" =~ ^(github|local)$ ]]; then
                error "Invalid source: $SOURCE (must be 'github' or 'local')"
                exit 1
            fi
            shift
            ;;
        --onsuccess=*)
            ON_SUCCESS="${1#*=}"
            if [[ ! "$ON_SUCCESS" =~ ^(ask|keep|delete)$ ]]; then
                error "Invalid onsuccess action: $ON_SUCCESS (must be 'ask', 'keep', or 'delete')"
                exit 1
            fi
            shift
            ;;
        --onfailure=*)
            ON_FAILURE="${1#*=}"
            if [[ ! "$ON_FAILURE" =~ ^(ask|keep|delete)$ ]]; then
                error "Invalid onfailure action: $ON_FAILURE (must be 'ask', 'keep', or 'delete')"
                exit 1
            fi
            shift
            ;;
        --local)
            SOURCE="local"
            shift
            ;;
        --github)
            SOURCE="github"
            shift
            ;;
        --keep)
            ON_SUCCESS="keep"
            ON_FAILURE="keep"
            shift
            ;;
        --delete)
            ON_SUCCESS="delete"
            ON_FAILURE="delete"
            shift
            ;;
        --verbose)
            VERBOSE=true
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

# Set defaults if not specified
if [ -z "$BASE_VM_NAME" ]; then
    BASE_VM_NAME="macOS Tahoe - base"
fi

if [ -z "$TEST_VM_NAME" ]; then
    # Generate random name with timestamp and random suffix
    RANDOM_SUFFIX=$(openssl rand -hex 4 2>/dev/null || echo $(date +%s | tail -c 5))
    TEST_VM_NAME="nix-me-test-$(date +%Y%m%d-%H%M%S)-${RANDOM_SUFFIX}"
fi

# Validate required parameters
if [ -z "$VM_USER" ]; then
    error "VM user is required. Use --vm-user=USERNAME"
    echo ""
    usage
fi

# Cleanup function
cleanup_vm() {
    local vm_name="$1"
    local should_delete="$2"

    if [ "$should_delete" = "true" ]; then
        log "Deleting test VM: $vm_name"
        $UTMCTL delete "$vm_name" 2>/dev/null || true
    else
        info "Keeping test VM: $vm_name"
        info "To delete manually, run: $UTMCTL delete '$vm_name'"
    fi
}

# Check prerequisites
check_prerequisites() {
    step "1/7" "Checking prerequisites"

    if [ ! -f "$UTMCTL" ]; then
        error "UTM not found. Please install UTM from https://mac.getutm.app/"
        exit 1
    fi

    if ! $UTMCTL list | grep -q "$BASE_VM_NAME"; then
        error "Base VM '$BASE_VM_NAME' not found"
        info "Available VMs:"
        $UTMCTL list
        exit 1
    fi

    log "Prerequisites check passed"
}

# Clone the base VM
clone_vm() {
    step "2/7" "Cloning base VM"

    log "Cloning '$BASE_VM_NAME' → '$TEST_VM_NAME'"

    if ! $UTMCTL clone "$BASE_VM_NAME" --name "$TEST_VM_NAME"; then
        error "Failed to clone VM"
        exit 1
    fi

    log "VM cloned successfully"
}

# Start the VM
start_vm() {
    step "3/7" "Starting test VM"

    log "Starting VM: $TEST_VM_NAME"

    if ! $UTMCTL start "$TEST_VM_NAME" --hide; then
        error "Failed to start VM"
        cleanup_vm "$TEST_VM_NAME" true
        exit 1
    fi

    # Note: Even if user provided base VM IP, the cloned VM gets a NEW IP
    # So we still need to scan or use guest agent to find the clone's IP
    log "VM started"
    log "Note: Cloned VM will get a new IP (different from base VM)"

    log "VM started, waiting for guest agent..."

    # Wait for VM to be ready (guest agent available)
    local elapsed=0
    while [ $elapsed -lt $VM_TIMEOUT ]; do
        # Check if we can get IP address (indicates guest agent is ready)
        if $UTMCTL ip-address "$TEST_VM_NAME" &>/dev/null; then
            log "VM is ready!"
            return 0
        fi

        sleep 5
        elapsed=$((elapsed + 5))
        echo -n "."
    done

    echo ""
    error "VM did not become ready within ${VM_TIMEOUT}s"
    error ""
    error "Without guest agent, you must provide the VM IP address manually."
    error "After the VM starts, find its IP via System Settings → Network"
    error "Then run with: --vm-ip=<IP_ADDRESS>"
    error ""
    error "Example: $0 --vm-user=$VM_USER --vm-ip=192.168.64.X --source=$SOURCE"
    $UTMCTL stop "$TEST_VM_NAME"
    cleanup_vm "$TEST_VM_NAME" true
    exit 1
}

# Get VM IP address
get_vm_ip() {
    # Note: --vm-ip flag is for reference only, cloned VM gets a NEW IP
    # So we ignore it here and try to auto-detect

    # Try utmctl ip-address (requires guest agent)
    local vm_ip=""
    vm_ip=$($UTMCTL ip-address "$TEST_VM_NAME" 2>/dev/null | head -1)

    if [ -n "$vm_ip" ] && [ "$vm_ip" != "unknown" ] && [ "$vm_ip" != "" ]; then
        echo "$vm_ip"
        return 0
    fi

    # If we already scanned and found an IP, use it
    if [ -n "$DETECTED_VM_IP" ]; then
        echo "$DETECTED_VM_IP"
        return 0
    fi

    echo "unknown"
    return 1
}

# Store detected IP globally
DETECTED_VM_IP=""

# Execute command in VM via SSH
vm_exec() {
    local cmd="$1"
    local vm_ip=$(get_vm_ip)

    if [ "$vm_ip" = "unknown" ]; then
        error "Could not get VM IP address"
        return 1
    fi

    local ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"
    if [ -n "$VM_SSH_KEY" ]; then
        ssh_opts="$ssh_opts -i $VM_SSH_KEY"
    fi

    if [ "$VERBOSE" = "true" ]; then
        log "Executing in VM ($vm_ip): $cmd"
    fi

    ssh $ssh_opts "$VM_USER@$vm_ip" "$cmd"
}

# Timeout function compatible with macOS
run_with_timeout() {
    local timeout_duration=$1
    shift
    local cmd="$@"

    # Run command in background
    eval "$cmd" &
    local cmd_pid=$!

    # Wait with timeout
    local elapsed=0
    while kill -0 $cmd_pid 2>/dev/null; do
        if [ $elapsed -ge $timeout_duration ]; then
            kill -TERM $cmd_pid 2>/dev/null
            sleep 2
            kill -KILL $cmd_pid 2>/dev/null
            return 124  # timeout exit code
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done

    # Get exit code
    wait $cmd_pid
    return $?
}

# Store IPs found before starting VM
EXISTING_SSH_IPS=""

# Scan for all IPs with SSH enabled on the network
scan_ssh_ips() {
    local subnet="192.168.64"
    local found_ips=""
    local ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=1 -o BatchMode=yes"

    for i in {2..20}; do  # Usually UTM assigns low IPs
        local test_ip="$subnet.$i"

        # Quick ping check
        if ping -c 1 -W 1 "$test_ip" &>/dev/null; then
            # Try SSH (ConnectTimeout handles the timeout)
            if ssh $ssh_opts "$VM_USER@$test_ip" "echo 'ok'" &>/dev/null 2>&1; then
                found_ips="$found_ips $test_ip"
            fi
        fi
    done

    echo "$found_ips"
}

# Scan for new VMs on the network (comparing to baseline)
scan_for_vm_ip() {
    log "Scanning network for new VM IP..."

    local subnet="192.168.64"
    local ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=2 -o BatchMode=yes"

    # Get current IPs with SSH
    local current_ips=$(scan_ssh_ips)

    # Find the NEW IP (not in EXISTING_SSH_IPS)
    for ip in $current_ips; do
        if [[ ! " $EXISTING_SSH_IPS " =~ " $ip " ]]; then
            log "Found new VM IP: $ip"
            echo "$ip"
            return 0
        fi
    done

    # If no new IP found, return the first one we find (maybe base VM wasn't running)
    for ip in $current_ips; do
        echo "$ip"
        return 0
    done

    echo "unknown"
    return 1
}

# Wait for SSH to be ready
wait_for_ssh() {
    step "4/7" "Waiting for SSH connectivity"

    local vm_ip=$(get_vm_ip)

    # If no IP provided and no guest agent, try to scan for it
    if [ "$vm_ip" = "unknown" ]; then
        warn "No VM IP provided and no guest agent available"
        log "Will scan network for VM after boot..."

        # Wait for VM to fully boot first
        log "Waiting 60 seconds for VM to boot and get network..."
        sleep 60

        vm_ip=$(scan_for_vm_ip)

        if [ "$vm_ip" = "unknown" ]; then
            error "Could not detect VM IP address"
            error ""
            error "Please provide the IP manually with --vm-ip=<IP>"
            error "Check the VM's network settings to find its IP"
            return 1
        fi

        log "Found VM at: $vm_ip"
        # Store for later use
        DETECTED_VM_IP="$vm_ip"
    fi

    log "VM IP: $vm_ip"
    log "Waiting for SSH to become available..."

    local ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5"
    if [ -n "$VM_SSH_KEY" ]; then
        ssh_opts="$ssh_opts -i $VM_SSH_KEY"
    fi

    local attempts=0
    while [ $attempts -lt 30 ]; do
        if ssh $ssh_opts "$VM_USER@$vm_ip" "echo 'SSH ready'" &>/dev/null; then
            log "SSH connection established"
            return 0
        fi

        sleep 2
        attempts=$((attempts + 1))
        echo -n "."
    done

    echo ""
    error "SSH did not become available within timeout"
    error "IP: $vm_ip"
    error ""
    error "Possible issues:"
    error "  1. Remote Login not enabled in VM"
    error "  2. Wrong IP address (cloned VM gets new IP)"
    error "  3. Password authentication required (try without --ssh-key)"
    error "  4. VM still booting"
    return 1
}

# Run installation in VM
run_installation() {
    step "5/7" "Running nix-me installation in VM"

    log "Installing nix-me (this will take 15-30 minutes)..."
    log "Testing complete installation flow (Homebrew will be installed)"

    local vm_ip=$(get_vm_ip)
    local ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"
    local scp_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
    if [ -n "$VM_SSH_KEY" ]; then
        ssh_opts="$ssh_opts -i $VM_SSH_KEY"
        scp_opts="$scp_opts -i $VM_SSH_KEY"
    fi

    local install_cmd=""
    # Set environment variables for VM testing
    # SKIP_MAS_APPS=1: Skip Mac App Store apps (iCloud doesn't work in VMs)
    # NON_INTERACTIVE=1: Don't prompt for user input
    local env_vars="SKIP_MAS_APPS=1 NON_INTERACTIVE=1"

    if [ "$SOURCE" = "github" ]; then
        install_cmd="$env_vars bash -c 'curl -fsSL https://raw.githubusercontent.com/lucamaraschi/nix-me/main/install.sh | bash'"
        log "Installing from GitHub"
    else
        log "Installing from local source"

        # Copy local project to VM
        local remote_dir="/tmp/nix-me-test-$$"
        log "Copying local files to VM at $remote_dir..."

        # Create remote directory
        ssh $ssh_opts "$VM_USER@$vm_ip" "mkdir -p $remote_dir" || {
            error "Failed to create remote directory"
            return 1
        }

        # Copy project files via scp (excluding .git, tests, docs, and other non-essential files)
        if ! scp $scp_opts -r \
            "$PROJECT_DIR/install.sh" \
            "$PROJECT_DIR/flake.nix" \
            "$PROJECT_DIR/flake.lock" \
            "$PROJECT_DIR/bin" \
            "$PROJECT_DIR/lib" \
            "$PROJECT_DIR/hosts" \
            "$PROJECT_DIR/modules" \
            "$VM_USER@$vm_ip:$remote_dir/"; then
            error "Failed to copy files to VM"
            return 1
        fi

        log "Local files copied successfully"

        # Run installation from local copy with VM environment variables
        install_cmd="cd $remote_dir && $env_vars bash install.sh"
    fi

    log "Running: $install_cmd"
    log "Environment: SKIP_MAS_APPS=1 (skipping Mac App Store apps)"

    # Run installation via SSH with timeout
    if run_with_timeout $INSTALL_TIMEOUT "ssh $ssh_opts '$VM_USER@$vm_ip' '$install_cmd'"; then
        log "Installation completed successfully!"
        return 0
    else
        local exit_code=$?
        if [ $exit_code -eq 124 ]; then
            error "Installation timed out after ${INSTALL_TIMEOUT}s"
        else
            error "Installation failed with exit code: $exit_code"
        fi
        return 1
    fi
}

# Run verification tests
run_verification() {
    step "6/7" "Running verification tests"

    log "Verifying nix-me installation..."

    local tests_passed=0
    local tests_total=0

    # Test 1: Check if nix is installed
    tests_total=$((tests_total + 1))
    if vm_exec "command -v nix" &>/dev/null; then
        log "✓ Nix is installed"
        tests_passed=$((tests_passed + 1))
    else
        error "✗ Nix not found"
    fi

    # Test 2: Check if darwin-rebuild exists
    tests_total=$((tests_total + 1))
    if vm_exec "command -v darwin-rebuild" &>/dev/null; then
        log "✓ darwin-rebuild is available"
        tests_passed=$((tests_passed + 1))
    else
        error "✗ darwin-rebuild not found"
    fi

    # Test 3: Check if config directory exists
    tests_total=$((tests_total + 1))
    if vm_exec "test -d ~/.config/nixpkgs" &>/dev/null; then
        log "✓ Configuration directory exists"
        tests_passed=$((tests_passed + 1))
    else
        error "✗ Configuration directory not found"
    fi

    # Test 4: Check if flake.nix exists
    tests_total=$((tests_total + 1))
    if vm_exec "test -f ~/.config/nixpkgs/flake.nix" &>/dev/null; then
        log "✓ flake.nix exists"
        tests_passed=$((tests_passed + 1))
    else
        error "✗ flake.nix not found"
    fi

    # Test 5: Check if nix-me CLI is available
    tests_total=$((tests_total + 1))
    if vm_exec "command -v nix-me" &>/dev/null; then
        log "✓ nix-me CLI is available"
        tests_passed=$((tests_passed + 1))
    else
        error "✗ nix-me CLI not found"
    fi

    echo ""
    log "Verification: $tests_passed/$tests_total tests passed"

    if [ $tests_passed -eq $tests_total ]; then
        return 0
    else
        return 1
    fi
}

# Main test flow
main() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  nix-me Automated VM Testing              ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════╝${NC}"
    echo ""

    info "Test VM name: $TEST_VM_NAME"
    info "Source: $SOURCE"
    if [ -n "$VM_IP" ]; then
        info "VM IP: $VM_IP (provided)"
    else
        info "VM IP: (will auto-detect via guest agent)"
    fi
    info "On success: $ON_SUCCESS"
    info "On failure: $ON_FAILURE"
    echo ""

    # Run test steps
    check_prerequisites
    clone_vm

    # Record existing SSH-enabled IPs before starting VM
    # This helps us identify the NEW VM's IP after it starts
    log "Recording existing SSH-enabled IPs on network..."
    EXISTING_SSH_IPS=$(scan_ssh_ips)
    if [ -n "$EXISTING_SSH_IPS" ]; then
        log "Found existing IPs:$EXISTING_SSH_IPS"
    else
        log "No existing SSH-enabled VMs found"
    fi

    # Set up cleanup trap
    trap "log 'Stopping VM...'; $UTMCTL stop '$TEST_VM_NAME' 2>/dev/null || true" EXIT

    start_vm
    wait_for_ssh

    # Run installation
    local install_success=false
    if run_installation; then
        install_success=true
    fi

    # Run verification if installation succeeded
    local verify_success=false
    if [ "$install_success" = "true" ]; then
        if run_verification; then
            verify_success=true
        fi
    fi

    # Stop VM
    step "7/7" "Cleaning up"
    log "Stopping VM..."
    $UTMCTL stop "$TEST_VM_NAME"

    # Decide on cleanup based on test result
    local cleanup_action=""
    if [ "$verify_success" = "true" ]; then
        cleanup_action="$ON_SUCCESS"
    else
        cleanup_action="$ON_FAILURE"
    fi

    local should_delete=false

    if [ "$cleanup_action" = "delete" ]; then
        should_delete=true
    elif [ "$cleanup_action" = "keep" ]; then
        should_delete=false
    else
        # Ask user
        echo ""
        if [ "$verify_success" = "true" ]; then
            echo -e "${GREEN}✓ All tests passed!${NC}"
        else
            echo -e "${RED}✗ Tests failed${NC}"
        fi
        echo ""
        read -p "$(echo -e ${YELLOW}Delete test VM? \(y/N\): ${NC})" answer
        if [[ $answer =~ ^[Yy] ]]; then
            should_delete=true
        else
            should_delete=false
        fi
    fi

    cleanup_vm "$TEST_VM_NAME" "$should_delete"

    # Final summary
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  Test Summary                              ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════╝${NC}"
    echo ""
    echo "  VM Name:         $TEST_VM_NAME"
    echo "  Installation:    $([ "$install_success" = "true" ] && echo -e "${GREEN}✓ Success${NC}" || echo -e "${RED}✗ Failed${NC}")"
    echo "  Verification:    $([ "$verify_success" = "true" ] && echo -e "${GREEN}✓ Success${NC}" || echo -e "${RED}✗ Failed${NC}")"
    echo "  VM Status:       $([ "$should_delete" = "true" ] && echo "Deleted" || echo "Kept for inspection")"
    echo ""

    if [ "$verify_success" = "true" ]; then
        log "VM testing completed successfully!"
        exit 0
    else
        error "VM testing failed"
        exit 1
    fi
}

# Run main
main
