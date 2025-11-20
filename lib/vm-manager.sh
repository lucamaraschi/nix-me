#!/usr/bin/env bash
# lib/vm-manager.sh - Interactive VM management with TUI
# Uses existing nix-me UI patterns for consistency

# Load UI library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/ui.sh"

# Constants
VM_DATA_DIR="$HOME/.local/share/nix-me/vms"
OMARCHY_VERSION="3.1"

# UTM path
UTM_APP="/Applications/UTM.app"
UTMCTL="$UTM_APP/Contents/MacOS/utmctl"

# VM Types
declare -A VM_TYPES=(
    ["test-macos"]="Test macOS VM (Test nix-me installation)"
    ["omarchy"]="Omarchy (Arch Linux + Hyprland by DHH)"
)

# VM Type Descriptions
declare -A VM_DESCRIPTIONS=(
    ["test-macos"]="Clone your base macOS VM to test nix-me installation. Useful for validating changes before applying to your main system."
    ["omarchy"]="Create a VM with Omarchy - Arch Linux + Hyprland tiling WM by DHH. Optionally layer your nix-me configs on top."
)

# Initialize directories
init_vm_dirs() {
    mkdir -p "$VM_DATA_DIR/isos"
    mkdir -p "$VM_DATA_DIR/configs"
    mkdir -p "$VM_DATA_DIR/scripts"
}

# Check UTM installation
check_utm() {
    if [[ ! -d "$UTM_APP" ]]; then
        print_error "UTM not found at $UTM_APP"
        print_info "Install UTM: brew install --cask utm"
        return 1
    fi
    return 0
}

# Main VM menu
vm_main_menu() {
    init_vm_dirs

    while true; do
        clear
        echo ""
        echo "  VM Management"
        echo ""
        echo -e "  ${GREEN}1${NC} Create new VM (test-macos or Omarchy)"
        echo -e "  ${GREEN}2${NC} List VMs"
        echo -e "  ${GREEN}3${NC} Start VM"
        echo -e "  ${GREEN}4${NC} Stop VM"
        echo -e "  ${GREEN}5${NC} Delete VM"
        echo ""
        echo -e "  ${GREEN}0${NC} Back"
        echo ""

        read -p "  Choose [0]: " choice
        choice=${choice:-0}

        case "$choice" in
            1) vm_create_wizard ;;
            2) vm_list ;;
            3) vm_start_menu ;;
            4) vm_stop_menu ;;
            5) vm_delete_menu ;;
            0|q|Q|"") return 0 ;;
        esac
    done
}

# VM Creation Wizard
vm_create_wizard() {
    clear
    print_header "Create New VM"
    echo ""

    # Step 1: Select VM type
    print_step 1 "Select VM Type"
    echo ""

    local vm_type
    if command -v fzf &>/dev/null; then
        vm_type=$(printf "%s\n" test-macos omarchy | \
            fzf --height=60% \
                --border=rounded \
                --prompt="Select VM type > " \
                --header="↑↓ Navigate | Enter: Select | ESC: Cancel" \
                --preview='case {} in
                    test-macos) echo "🧪 Test macOS VM"; echo ""; echo "Clone your base macOS VM to test nix-me installation."; echo "Perfect for validating changes before applying to your main system."; echo ""; echo "✨ Features:"; echo "  • Full installation testing"; echo "  • Auto-delete on success"; echo "  • Test from local or GitHub"; echo "  • Complete automation" ;;
                    omarchy) echo "🎨 Omarchy VM"; echo ""; echo "Arch Linux + Hyprland tiling WM by DHH."; echo "Beautiful, minimal, keyboard-driven environment."; echo ""; echo "✨ Features:"; echo "  • Hyprland tiling WM"; echo "  • Neovim, Alacritty"; echo "  • Optional nix-me layer"; echo "  • Modern dev setup"; echo ""; echo "📦 Automatic ISO download included!" ;;
                esac' \
                --preview-window=right:60%:wrap)
    else
        echo -e "  ${GREEN}[1]${NC} test-macos"
        echo -e "      Test your nix-me installation in a VM"
        echo ""
        echo -e "  ${GREEN}[2]${NC} omarchy"
        echo -e "      Arch Linux + Hyprland by DHH"
        echo ""
        echo -e "  ${GREEN}[0]${NC} Cancel"
        echo ""
        read -p "  Select type [0]: " type_choice
        case "${type_choice}" in
            1) vm_type="test-macos" ;;
            2) vm_type="omarchy" ;;
            0|"") return 0 ;;
        esac
    fi

    [[ -z "$vm_type" ]] && return 0

    clear
    print_header "Create New VM"
    print_success "Selected: $vm_type"
    echo ""

    # Handle test-macos differently
    if [[ "$vm_type" == "test-macos" ]]; then
        vm_create_test_macos
        return $?
    fi

    # Step 2: VM Name
    print_step 2 "VM Configuration"
    local default_name="${vm_type}-$(date +%Y%m%d)"
    read -p "$(echo -e ${CYAN}VM Name${NC} [$default_name] \(0=cancel\): )" vm_name
    [[ "$vm_name" == "0" ]] && return 0
    vm_name=${vm_name:-$default_name}

    # Step 3: Resources
    echo ""
    print_step 3 "Resource Allocation"

    local total_mem=$(sysctl -n hw.memsize 2>/dev/null)
    local total_mem_gb=$((total_mem / 1024 / 1024 / 1024))
    local default_mem=$((total_mem_gb / 2 * 1024))  # Half of system RAM in MB
    [[ $default_mem -gt 16384 ]] && default_mem=16384
    [[ $default_mem -lt 4096 ]] && default_mem=4096

    local total_cpus=$(sysctl -n hw.ncpu 2>/dev/null)
    local default_cpus=$((total_cpus / 2))
    [[ $default_cpus -lt 2 ]] && default_cpus=2
    [[ $default_cpus -gt 8 ]] && default_cpus=8

    echo -e "  ${BULLET} System: ${total_mem_gb}GB RAM, ${total_cpus} CPUs"
    echo ""

    read -p "$(echo -e ${CYAN}Memory \(MB\)${NC} [$default_mem] \(0=cancel\): )" memory
    [[ "$memory" == "0" ]] && return 0
    memory=${memory:-$default_mem}

    read -p "$(echo -e ${CYAN}CPU Cores${NC} [$default_cpus] \(0=cancel\): )" cpus
    [[ "$cpus" == "0" ]] && return 0
    cpus=${cpus:-$default_cpus}

    read -p "$(echo -e ${CYAN}Disk Size${NC} [80G] \(0=cancel\): )" disk_size
    [[ "$disk_size" == "0" ]] && return 0
    disk_size=${disk_size:-80G}

    echo ""

    # Step 4: Summary
    clear
    print_header "Create New VM"
    print_step 4 "Configuration Summary"
    echo ""
    echo -e "  ${BULLET} Type: ${GREEN}$vm_type${NC}"
    echo -e "  ${BULLET} Name: ${GREEN}$vm_name${NC}"
    echo -e "  ${BULLET} Memory: ${GREEN}${memory}MB${NC}"
    echo -e "  ${BULLET} CPUs: ${GREEN}$cpus${NC}"
    echo -e "  ${BULLET} Disk: ${GREEN}$disk_size${NC}"
    echo ""

    if ! ask_yes_no "Create this VM?" "y"; then
        print_warn "VM creation cancelled"
        sleep 1
        return 0
    fi

    echo ""
    print_step 5 "Preparing VM"

    # Check for ISO (Omarchy only)
    local iso_path
    case "$vm_type" in
        omarchy)
            iso_path="$VM_DATA_DIR/isos/omarchy-${OMARCHY_VERSION}.iso"
            if [[ ! -f "$iso_path" ]]; then
                echo ""
                print_info "📦 Downloading Omarchy ISO..."
                echo ""
                print_info "The ISO will be cached at:"
                echo -e "  ${CYAN}$iso_path${NC}"
                echo ""

                if ! vm_download_omarchy_iso; then
                    print_error "Failed to download ISO"
                    sleep 2
                    return 1
                fi
            else
                print_success "Using cached ISO: $(basename "$iso_path")"
            fi
            ;;
    esac

    # Create VM via UTM
    if ! check_utm; then
        sleep 3
        return 1
    fi

    # Create UTM VM configuration
    local vm_config_dir="$VM_DATA_DIR/configs/$vm_name"
    mkdir -p "$vm_config_dir"

    # Generate setup instructions
    generate_vm_instructions "$vm_type" "$vm_name" "$memory" "$cpus" "$disk_size" "$iso_path" "$vm_config_dir"

    print_success "VM configuration created!"
    echo ""
    echo -e "  ${BULLET} Config: ${CYAN}$vm_config_dir${NC}"
    echo -e "  ${BULLET} Instructions: ${CYAN}$vm_config_dir/README.md${NC}"
    echo ""

    if ask_yes_no "Open setup instructions?" "y"; then
        if command -v open &>/dev/null; then
            open "$vm_config_dir/README.md"
        else
            cat "$vm_config_dir/README.md"
        fi
    fi

    if ask_yes_no "Create VM in UTM now?" "y"; then
        vm_create_in_utm "$vm_name" "$memory" "$cpus" "$disk_size" "$iso_path"
    fi

    echo ""
    read -p "Press Enter to continue..."
}

# Test macOS VM Creation
vm_create_test_macos() {
    print_step 2 "Test VM Configuration"
    echo ""

    # Check for base VM
    if ! check_utm; then
        sleep 2
        return 1
    fi

    local vms=$("$UTMCTL" list 2>/dev/null | tail -n +2)
    if [[ -z "$vms" ]]; then
        print_error "No VMs found in UTM to clone from"
        print_info "Create a base macOS VM first"
        sleep 3
        return 1
    fi

    # Select base VM to clone
    local base_vm
    if command -v fzf &>/dev/null; then
        base_vm=$(echo "$vms" | fzf --height=50% \
                                     --border=rounded \
                                     --prompt="Select base VM to clone > " \
                                     --header="Choose your clean macOS VM" | awk '{print $NF}')
    else
        echo -e "${CYAN}Available VMs:${NC}"
        echo "$vms"
        echo ""
        read -p "$(echo -e ${CYAN}Base VM name to clone${NC}: )" base_vm
    fi

    [[ -z "$base_vm" ]] && return 0

    clear
    print_header "Test macOS VM"
    print_success "Base VM: $base_vm"
    echo ""

    # VM name
    print_step 3 "Test VM Name"
    local default_name="test-$(date +%Y%m%d-%H%M%S)"
    read -p "$(echo -e ${CYAN}Test VM name${NC} [$default_name] \(0=cancel\): )" test_vm_name
    [[ "$test_vm_name" == "0" ]] && return 0
    test_vm_name=${test_vm_name:-$default_name}

    echo ""

    # Test source
    print_step 4 "Test Source"
    echo ""
    echo -e "  ${CYAN}[1]${NC} GitHub (test published version)"
    echo -e "  ${CYAN}[2]${NC} Local (test your current changes)"
    echo ""
    read -p "$(echo -e ${CYAN}Source${NC} [2]: )" source_choice
    local test_source="local"
    case "${source_choice:-2}" in
        1) test_source="github" ;;
        2) test_source="local" ;;
    esac

    echo ""
    print_success "Source: $test_source"
    echo ""

    # Options
    print_step 5 "Test Options"
    echo ""

    local delete_on_success="ask"
    local delete_on_failure="keep"
    local vm_user=""
    local vm_ip=""

    # Ask about deletion behavior
    echo -e "  ${CYAN}Delete VM on successful test?${NC}"
    echo -e "    [1] Ask me"
    echo -e "    [2] Auto-delete (clean up automatically)"
    echo -e "    [3] Keep (inspect manually)"
    echo ""
    read -p "$(echo -e ${CYAN}On success${NC} [1]: )" success_choice
    case "${success_choice:-1}" in
        1) delete_on_success="ask" ;;
        2) delete_on_success="delete" ;;
        3) delete_on_success="keep" ;;
    esac

    echo ""
    echo -e "  ${CYAN}Delete VM on failed test?${NC}"
    echo -e "    [1] Keep (recommended for debugging)"
    echo -e "    [2] Auto-delete"
    echo ""
    read -p "$(echo -e ${CYAN}On failure${NC} [1]: )" failure_choice
    case "${failure_choice:-1}" in
        1) delete_on_failure="keep" ;;
        2) delete_on_failure="delete" ;;
    esac

    echo ""

    # VM user (required for SSH)
    read -p "$(echo -e ${CYAN}VM username \(for SSH\)${NC} [$USER]: )" vm_user
    vm_user=${vm_user:-$USER}

    echo ""

    # Summary
    clear
    print_header "Test VM Summary"
    echo ""
    echo -e "  ${BULLET} Base VM: ${GREEN}$base_vm${NC}"
    echo -e "  ${BULLET} Test VM: ${GREEN}$test_vm_name${NC}"
    echo -e "  ${BULLET} Source: ${GREEN}$test_source${NC}"
    echo -e "  ${BULLET} VM User: ${GREEN}$vm_user${NC}"
    echo -e "  ${BULLET} On Success: ${GREEN}$delete_on_success${NC}"
    echo -e "  ${BULLET} On Failure: ${GREEN}$delete_on_failure${NC}"
    echo ""

    if ! ask_yes_no "Start test?" "y"; then
        print_warn "Test cancelled"
        sleep 1
        return 0
    fi

    # Run the test
    echo ""
    print_info "Starting VM test..."
    echo ""

    local test_script="$SCRIPT_DIR/../tests/vm-test.sh"
    if [[ ! -f "$test_script" ]]; then
        print_error "Test script not found: $test_script"
        sleep 2
        return 1
    fi

    # Build command
    local test_cmd="$test_script"
    test_cmd="$test_cmd --base-vm=\"$base_vm\""
    test_cmd="$test_cmd --name=\"$test_vm_name\""
    test_cmd="$test_cmd --vm-user=\"$vm_user\""
    test_cmd="$test_cmd --source=$test_source"
    test_cmd="$test_cmd --onsuccess=$delete_on_success"
    test_cmd="$test_cmd --onfailure=$delete_on_failure"

    print_info "Running: $test_cmd"
    echo ""

    # Execute the test
    eval "$test_cmd"
    local exit_code=$?

    echo ""
    if [[ $exit_code -eq 0 ]]; then
        print_success "Test completed successfully!"
    else
        print_error "Test failed (exit code: $exit_code)"
    fi

    echo ""
    read -p "Press Enter to continue..."
    return $exit_code
}

# Generate VM setup instructions
generate_vm_instructions() {
    local vm_type="$1"
    local vm_name="$2"
    local memory="$3"
    local cpus="$4"
    local disk_size="$5"
    local iso_path="$6"
    local config_dir="$7"

    case "$vm_type" in
        omarchy)
            generate_omarchy_instructions "$vm_name" "$memory" "$cpus" "$disk_size" "$iso_path" "$config_dir"
            ;;
        nixos)
            generate_nixos_instructions "$vm_name" "$memory" "$cpus" "$disk_size" "$iso_path" "$config_dir"
            ;;
        ubuntu)
            generate_ubuntu_instructions "$vm_name" "$memory" "$cpus" "$disk_size" "$iso_path" "$config_dir"
            ;;
    esac
}

# Generate Omarchy-specific instructions
generate_omarchy_instructions() {
    local vm_name="$1" memory="$2" cpus="$3" disk_size="$4" iso_path="$5" config_dir="$6"

    cat > "$config_dir/README.md" << EOF
# Omarchy VM: $vm_name

**Arch Linux + Hyprland by DHH**

## VM Specs
- Memory: ${memory}MB
- CPUs: $cpus
- Disk: $disk_size
- ISO: $iso_path

## Installation Steps

### 1. Create VM in UTM
Already done if you selected "Create VM in UTM now".

### 2. Boot and Install Omarchy
1. Start the VM in UTM
2. Boot from the ISO
3. Follow the Omarchy installer (automated, 2-10 min)
4. Create your user account
5. Reboot into the installed system

### 3. First Boot
- **Desktop**: Hyprland tiling WM
- **Terminal**: Super + Enter
- **App Launcher**: Super + D
- **Close Window**: Super + Q

### 4. Apply nix-me Configuration (Optional)

Layer your Fish shell, kubectl, k3d configs on top:

\`\`\`bash
# Install Nix package manager
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install

# Source Nix
. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh

# Clone nix-me
git clone https://github.com/lucamaraschi/nix-me.git ~/.config/nixpkgs

# Apply home-manager config
nix run home-manager/master -- switch --flake ~/.config/nixpkgs#omarchy-aarch64

# Optional: Switch to Fish shell
sudo pacman -S fish
chsh -s \$(which fish)
\`\`\`

### What nix-me Adds
- Fish shell with starship prompt
- kubectl, k3d, helm
- gh CLI, lazygit, delta
- bat, eza, ripgrep, fd, fzf
- Git, tmux, direnv configs

Enjoy your Omarchy VM!
EOF
}

# Generate NixOS instructions
generate_nixos_instructions() {
    local vm_name="$1" memory="$2" cpus="$3" disk_size="$4" iso_path="$5" config_dir="$6"

    cat > "$config_dir/README.md" << EOF
# NixOS VM: $vm_name

**Declarative Linux with GNOME Desktop**

## VM Specs
- Memory: ${memory}MB
- CPUs: $cpus
- Disk: $disk_size
- ISO: $iso_path

## Installation Steps

### 1. Boot and Partition Disk

\`\`\`bash
# Partition (UEFI)
sudo parted /dev/vda -- mklabel gpt
sudo parted /dev/vda -- mkpart primary 512MB -8GB
sudo parted /dev/vda -- mkpart primary linux-swap -8GB 100%
sudo parted /dev/vda -- mkpart ESP fat32 1MB 512MB
sudo parted /dev/vda -- set 3 esp on

# Format
sudo mkfs.ext4 -L nixos /dev/vda1
sudo mkswap -L swap /dev/vda2
sudo mkfs.fat -F 32 -n boot /dev/vda3

# Mount
sudo mount /dev/disk/by-label/nixos /mnt
sudo mkdir -p /mnt/boot
sudo mount /dev/disk/by-label/boot /mnt/boot
sudo swapon /dev/disk/by-label/swap

# Install
sudo nixos-generate-config --root /mnt
sudo nixos-install
sudo reboot
\`\`\`

### 2. Apply nix-me Configuration

\`\`\`bash
git clone https://github.com/lucamaraschi/nix-me.git ~/.config/nixpkgs
sudo cp /etc/nixos/hardware-configuration.nix ~/.config/nixpkgs/hosts/omarchy-vm/
sudo nixos-rebuild switch --flake ~/.config/nixpkgs#omarchy-vm
sudo reboot
\`\`\`

### Default User
- Username: dev
- Password: dev (change immediately!)

Enjoy your NixOS VM!
EOF
}

# Generate Ubuntu instructions
generate_ubuntu_instructions() {
    local vm_name="$1" memory="$2" cpus="$3" disk_size="$4" iso_path="$5" config_dir="$6"

    cat > "$config_dir/README.md" << EOF
# Ubuntu VM: $vm_name

**Ubuntu Server**

## VM Specs
- Memory: ${memory}MB
- CPUs: $cpus
- Disk: $disk_size
- ISO: $iso_path

## Installation
Follow the Ubuntu installer prompts.

## Apply nix-me Configuration

\`\`\`bash
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
git clone https://github.com/lucamaraschi/nix-me.git ~/.config/nixpkgs
nix run home-manager/master -- switch --flake ~/.config/nixpkgs#omarchy-aarch64
\`\`\`

Enjoy your Ubuntu VM!
EOF
}

# Create VM directly in UTM (basic implementation)
vm_create_in_utm() {
    local vm_name="$1"
    local memory="$2"
    local cpus="$3"
    local disk_size="$4"
    local iso_path="$5"

    print_info "Creating VM in UTM..."

    # UTM doesn't have a direct CLI for VM creation
    # We'll open UTM and provide instructions
    if [[ -d "$UTM_APP" ]]; then
        open -a UTM
        print_info "UTM opened. Create VM manually with:"
        echo -e "  ${BULLET} Name: $vm_name"
        echo -e "  ${BULLET} Type: Virtualize > Linux"
        echo -e "  ${BULLET} ISO: $iso_path"
        echo -e "  ${BULLET} Memory: ${memory}MB"
        echo -e "  ${BULLET} CPUs: $cpus"
        echo -e "  ${BULLET} Disk: $disk_size"
    else
        print_error "UTM not found"
    fi
}

# List VMs
vm_list() {
    clear
    print_header "VM List"
    echo ""

    if check_utm; then
        print_info "UTM Virtual Machines:"
        echo ""
        "$UTMCTL" list 2>/dev/null || print_warn "Could not list UTM VMs"
    fi

    echo ""
    print_info "nix-me VM Configurations:"
    echo ""

    if [[ -d "$VM_DATA_DIR/configs" ]]; then
        local found=false
        for config in "$VM_DATA_DIR/configs"/*; do
            if [[ -d "$config" ]]; then
                local name=$(basename "$config")
                echo -e "  ${BULLET} $name"
                found=true
            fi
        done
        if [[ "$found" == "false" ]]; then
            echo -e "  ${BULLET} (none)"
        fi
    fi

    echo ""
    read -p "Press Enter to continue..."
}

# Start VM menu
vm_start_menu() {
    clear
    print_header "Start VM"
    echo ""

    if ! check_utm; then
        sleep 2
        return 1
    fi

    local vms=$("$UTMCTL" list 2>/dev/null | tail -n +2)
    if [[ -z "$vms" ]]; then
        print_warn "No VMs found in UTM"
        sleep 2
        return 1
    fi

    local vm_name
    if command -v fzf &>/dev/null; then
        vm_name=$(echo "$vms" | fzf --height=40% \
                                     --border=rounded \
                                     --prompt="Select VM to start > " \
                                     --header="Choose a VM" | awk '{print $NF}')
    else
        echo "$vms"
        echo ""
        read -p "$(echo -e ${CYAN}VM name to start${NC}: )" vm_name
    fi

    if [[ -n "$vm_name" ]]; then
        print_info "Starting $vm_name..."
        "$UTMCTL" start "$vm_name" 2>/dev/null && print_success "VM started" || print_error "Failed to start VM"
    fi

    sleep 2
}

# Stop VM menu
vm_stop_menu() {
    clear
    print_header "Stop VM"
    echo ""

    if ! check_utm; then
        sleep 2
        return 1
    fi

    local vms=$("$UTMCTL" list 2>/dev/null | grep "started" | awk '{print $NF}')
    if [[ -z "$vms" ]]; then
        print_warn "No running VMs found"
        sleep 2
        return 1
    fi

    local vm_name
    if command -v fzf &>/dev/null; then
        vm_name=$(echo "$vms" | fzf --height=40% \
                                     --border=rounded \
                                     --prompt="Select VM to stop > " \
                                     --header="Choose a running VM")
    else
        echo "Running VMs:"
        echo "$vms"
        echo ""
        read -p "$(echo -e ${CYAN}VM name to stop${NC}: )" vm_name
    fi

    if [[ -n "$vm_name" ]]; then
        print_info "Stopping $vm_name..."
        "$UTMCTL" stop "$vm_name" 2>/dev/null && print_success "VM stopped" || print_error "Failed to stop VM"
    fi

    sleep 2
}

# Delete VM menu
vm_delete_menu() {
    clear
    print_header "Delete VM"
    echo ""

    print_warn "This will permanently delete the VM!"
    echo ""

    if ! check_utm; then
        sleep 2
        return 1
    fi

    local vms=$("$UTMCTL" list 2>/dev/null | tail -n +2)
    if [[ -z "$vms" ]]; then
        print_warn "No VMs found"
        sleep 2
        return 1
    fi

    local vm_name
    if command -v fzf &>/dev/null; then
        vm_name=$(echo "$vms" | fzf --height=40% \
                                     --border=rounded \
                                     --prompt="Select VM to DELETE > " \
                                     --header="⚠️  WARNING: This is permanent!" | awk '{print $NF}')
    else
        echo "$vms"
        echo ""
        read -p "$(echo -e ${RED}VM name to DELETE${NC}: )" vm_name
    fi

    if [[ -n "$vm_name" ]]; then
        if ask_yes_no "Really delete $vm_name?" "n"; then
            print_info "Deleting $vm_name..."
            "$UTMCTL" delete "$vm_name" 2>/dev/null && print_success "VM deleted" || print_error "Failed to delete VM"

            # Also remove config
            if [[ -d "$VM_DATA_DIR/configs/$vm_name" ]]; then
                rm -rf "$VM_DATA_DIR/configs/$vm_name"
                print_info "Removed configuration directory"
            fi
        else
            print_info "Cancelled"
        fi
    fi

    sleep 2
}

# Download ISO menu
vm_download_iso_menu() {
    clear
    print_header "Download ISOs"
    echo ""
    echo -e "  ${CYAN}[1]${NC} Omarchy (Arch + Hyprland)"
    echo -e "  ${CYAN}[2]${NC} NixOS (GNOME)"
    echo -e "  ${CYAN}[3]${NC} Ubuntu Server"
    echo ""
    echo -e "  ${CYAN}[0]${NC} Back"
    echo ""

    read -p "$(echo -e ${CYAN}Select ISO${NC} [0]: )" choice
    choice=${choice:-0}

    case "$choice" in
        1) vm_download_omarchy_iso ;;
        2) vm_download_nixos_iso ;;
        3) vm_download_ubuntu_iso ;;
        0) return 0 ;;
    esac

    read -p "Press Enter to continue..."
}

# Download Omarchy ISO
vm_download_omarchy_iso() {
    local iso_path="$VM_DATA_DIR/isos/omarchy-${OMARCHY_VERSION}.iso"

    if [[ -f "$iso_path" ]]; then
        print_success "✓ Omarchy ISO already cached"
        return 0
    fi

    print_info "Opening browser to download Omarchy ISO..."
    echo ""
    echo -e "  ${YELLOW}Manual download required${NC}"
    echo -e "  ${BULLET} Browser will open: ${CYAN}https://omarchy.org/${NC}"
    echo -e "  ${BULLET} Click: ${GREEN}'Download the ISO'${NC}"
    echo -e "  ${BULLET} Save as: ${CYAN}omarchy-${OMARCHY_VERSION}.iso${NC}"
    echo -e "  ${BULLET} Move to: ${CYAN}$(dirname "$iso_path")/${NC}"
    echo ""

    # Open browser
    if command -v open &>/dev/null; then
        open "https://omarchy.org/"
    fi

    echo -e "  ${YELLOW}Waiting for ISO download...${NC}"
    echo ""

    # Wait for user to download
    local attempts=0
    while [[ $attempts -lt 60 ]]; do
        if [[ -f "$iso_path" ]]; then
            print_success "✓ ISO downloaded successfully!"
            return 0
        fi

        # Show progress indicator
        echo -ne "  \r  Checking... ${attempts}s (Press Ctrl+C to cancel)  "
        sleep 5
        attempts=$((attempts + 5))
    done

    echo ""
    print_error "ISO download timeout"
    print_info "Please download manually and place at:"
    echo -e "  ${CYAN}$iso_path${NC}"
    return 1
}

# Download NixOS ISO
vm_download_nixos_iso() {
    local iso_path="$VM_DATA_DIR/isos/nixos-gnome-24.11-aarch64-linux.iso"

    if [[ -f "$iso_path" ]]; then
        print_success "NixOS ISO already exists: $iso_path"
        return 0
    fi

    print_info "Downloading NixOS 24.11 GNOME ISO..."
    local iso_url="https://channels.nixos.org/nixos-24.11/latest-nixos-gnome-aarch64-linux.iso"

    curl -L --progress-bar -o "$iso_path" "$iso_url" && \
        print_success "Downloaded to $iso_path" || \
        print_error "Download failed"
}

# Download Ubuntu ISO
vm_download_ubuntu_iso() {
    local iso_path="$VM_DATA_DIR/isos/ubuntu-24.04-live-server-arm64.iso"

    if [[ -f "$iso_path" ]]; then
        print_success "Ubuntu ISO already exists: $iso_path"
        return 0
    fi

    print_info "Ubuntu ISO must be downloaded manually"
    echo ""
    echo -e "  ${BULLET} Visit: ${CYAN}https://ubuntu.com/download/server/arm${NC}"
    echo -e "  ${BULLET} Download: Ubuntu 24.04 LTS ARM64"
    echo -e "  ${BULLET} Save to: ${CYAN}$iso_path${NC}"
    echo ""

    if ask_yes_no "Open Ubuntu download page?" "y"; then
        open "https://ubuntu.com/download/server/arm"
    fi
}

# Apply nix-me config menu
vm_apply_config_menu() {
    clear
    print_header "Apply nix-me Configuration"
    echo ""

    print_info "This will apply your nix-me configs to a running VM via SSH."
    echo ""

    if ! check_utm; then
        sleep 2
        return 1
    fi

    # Get running VMs
    local vms=$("$UTMCTL" list 2>/dev/null | grep "started" | awk '{print $NF}')
    if [[ -z "$vms" ]]; then
        print_warn "No running VMs found. Start a VM first."
        sleep 2
        return 1
    fi

    local vm_name
    if command -v fzf &>/dev/null; then
        vm_name=$(echo "$vms" | fzf --height=40% \
                                     --border=rounded \
                                     --prompt="Select VM > " \
                                     --header="Choose a running VM")
    else
        echo "Running VMs:"
        echo "$vms"
        echo ""
        read -p "$(echo -e ${CYAN}VM name${NC}: )" vm_name
    fi

    [[ -z "$vm_name" ]] && return 1

    # Get SSH details
    echo ""
    read -p "$(echo -e ${CYAN}SSH Host/IP${NC} [localhost]: )" ssh_host
    ssh_host=${ssh_host:-localhost}

    read -p "$(echo -e ${CYAN}SSH Port${NC} [22]: )" ssh_port
    ssh_port=${ssh_port:-22}

    read -p "$(echo -e ${CYAN}SSH User${NC} [dev]: )" ssh_user
    ssh_user=${ssh_user:-dev}

    echo ""
    print_info "Will apply nix-me config to $ssh_user@$ssh_host:$ssh_port"

    if ! ask_yes_no "Proceed?" "y"; then
        return 1
    fi

    # Test SSH connection
    print_info "Testing SSH connection..."
    if ! ssh -p "$ssh_port" -o ConnectTimeout=5 -o BatchMode=yes "$ssh_user@$ssh_host" "echo 'SSH OK'" 2>/dev/null; then
        print_error "Cannot connect via SSH"
        print_info "Make sure:"
        echo -e "  ${BULLET} VM is running"
        echo -e "  ${BULLET} SSH is enabled in VM"
        echo -e "  ${BULLET} Correct credentials"
        sleep 3
        return 1
    fi

    print_success "SSH connection OK"
    echo ""

    # Apply configuration
    print_info "Installing Nix and applying configuration..."
    ssh -p "$ssh_port" "$ssh_user@$ssh_host" << 'REMOTE_SCRIPT'
set -e
echo "Installing Nix..."
if ! command -v nix &>/dev/null; then
    curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --no-confirm
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

echo "Cloning nix-me..."
if [[ ! -d ~/.config/nixpkgs ]]; then
    git clone https://github.com/lucamaraschi/nix-me.git ~/.config/nixpkgs
else
    cd ~/.config/nixpkgs && git pull
fi

echo "Applying home-manager configuration..."
cd ~/.config/nixpkgs
nix run home-manager/master -- switch --flake .#omarchy-aarch64

echo "Done!"
REMOTE_SCRIPT

    if [[ $? -eq 0 ]]; then
        print_success "Configuration applied successfully!"
    else
        print_error "Configuration failed"
    fi

    sleep 2
}

# Export main function
export -f vm_main_menu
