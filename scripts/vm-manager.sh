#!/bin/bash
# scripts/vm-manager.sh - Fully Automated VM Manager for nix-me
set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NIX_ME_DIR="$(dirname "$SCRIPT_DIR")"
VM_BASE_DIR="$HOME/.local/share/nix-me/vms"
ISO_CACHE_DIR="$HOME/.local/share/nix-me/cache"
STATE_FILE="$VM_BASE_DIR/.vm-state.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Logging functions
log() { echo -e "${BLUE}[vm-manager]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
header() { echo -e "${PURPLE}=== $1 ===${NC}"; }

# Detect architecture and set ISO URL
detect_arch() {
    case "$(uname -m)" in
        arm64|aarch64) echo "aarch64" ;;
        x86_64) echo "x86_64" ;;
        *) error "Unsupported architecture: $(uname -m)" ;;
    esac
}

get_iso_info() {
    local arch="$1"
    local version="23.11"
    local build="5426.96e18717904d"
    
    case "$arch" in
        aarch64)
            echo "https://releases.nixos.org/nixos/$version/nixos-$version.$build/nixos-minimal-$version.$build-aarch64-linux.iso"
            ;;
        x86_64)
            echo "https://releases.nixos.org/nixos/$version/nixos-$version.$build/nixos-minimal-$version.$build-x86_64-linux.iso"
            ;;
    esac
}

# Check dependencies
check_dependencies() {
    local missing=()
    
    command -v curl >/dev/null || missing+=("curl")
    command -v jq >/dev/null || missing+=("jq")
    
    if [[ "$(uname -s)" == "Darwin" ]]; then
        if ! command -v utm >/dev/null && ! command -v qemu-system-aarch64 >/dev/null; then
            missing+=("utm or qemu")
        fi
    else
        command -v qemu-system-x86_64 >/dev/null || missing+=("qemu")
    fi
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing dependencies: ${missing[*]}"
    fi
}

# Install missing dependencies automatically
install_dependencies() {
    log "Installing missing dependencies..."
    
    if [[ "$(uname -s)" == "Darwin" ]]; then
        if ! command -v brew >/dev/null; then
            log "Installing Homebrew..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        fi
        
        # Install required packages
        local packages=()
        command -v utm >/dev/null || packages+=("--cask utm")
        command -v qemu-system-aarch64 >/dev/null || packages+=("qemu")
        command -v jq >/dev/null || packages+=("jq")
        
        if [[ ${#packages[@]} -gt 0 ]]; then
            brew install "${packages[@]}"
        fi
    fi
    
    success "Dependencies installed"
}

# State management
init_state() {
    mkdir -p "$VM_BASE_DIR" "$ISO_CACHE_DIR"
    if [[ ! -f "$STATE_FILE" ]]; then
        echo '{"vms": {}, "version": "1.0"}' > "$STATE_FILE"
    fi
}

get_vm_state() {
    local vm_name="$1"
    jq -r ".vms[\"$vm_name\"] // empty" "$STATE_FILE" 2>/dev/null || echo ""
}

set_vm_state() {
    local vm_name="$1"
    local state="$2"
    local tmp_file
    tmp_file=$(mktemp)
    
    jq ".vms[\"$vm_name\"] = $state" "$STATE_FILE" > "$tmp_file"
    mv "$tmp_file" "$STATE_FILE"
}

list_vms() {
    jq -r '.vms | keys[]' "$STATE_FILE" 2>/dev/null || true
}

# Download NixOS ISO automatically
download_iso() {
    local arch="$1"
    local iso_url
    local iso_filename
    local iso_path
    
    iso_url=$(get_iso_info "$arch")
    iso_filename=$(basename "$iso_url")
    iso_path="$ISO_CACHE_DIR/$iso_filename"
    
    if [[ -f "$iso_path" ]]; then
        log "ISO already cached: $iso_filename"
        echo "$iso_path"
        return 0
    fi
    
    log "Downloading NixOS ISO for $arch..."
    log "URL: $iso_url"
    
    if curl -L --fail --progress-bar "$iso_url" -o "$iso_path.tmp"; then
        mv "$iso_path.tmp" "$iso_path"
        success "ISO downloaded: $iso_filename"
        echo "$iso_path"
    else
        rm -f "$iso_path.tmp"
        error "Failed to download ISO"
    fi
}

# Create automated installation configuration
create_autoinstall_config() {
    local vm_name="$1"
    local vm_dir="$2"
    
    # Create a custom configuration that automates the installation
    cat > "$vm_dir/autoinstall.nix" << EOF
{ config, lib, pkgs, ... }:

{
  imports = [
    <nixpkgs/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix>
  ];

  # Auto-installation configuration
  systemd.services.auto-install = {
    description = "Automated NixOS Installation";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    script = ''
      # Wait for system to be ready
      sleep 30
      
      # Partition the disk
      parted /dev/vda -- mklabel gpt
      parted /dev/vda -- mkpart primary 512MiB -8GiB
      parted /dev/vda -- mkpart primary linux-swap -8GiB 100%
      parted /dev/vda -- mkpart ESP fat32 1MiB 512MiB
      parted /dev/vda -- set 3 esp on
      
      # Format partitions
      mkfs.ext4 -L nixos /dev/vda1
      mkswap -L swap /dev/vda2
      swapon /dev/vda2
      mkfs.fat -F 32 -n boot /dev/vda3
      
      # Mount partitions
      mount /dev/disk/by-label/nixos /mnt
      mkdir -p /mnt/boot
      mount /dev/disk/by-label/boot /mnt/boot
      
      # Generate hardware configuration
      nixos-generate-config --root /mnt
      
      # Copy our nix-me configuration
      mkdir -p /mnt/etc/nixos/nix-me
      cp -r /mnt/media/cdrom/nix-me/* /mnt/etc/nixos/nix-me/
      
      # Use our VM configuration
      cp /mnt/etc/nixos/nix-me/hosts/nixos-vm/default.nix /mnt/etc/nixos/configuration.nix
      
      # Install NixOS
      nixos-install --no-root-passwd
      
      # Signal completion
      touch /mnt/installation-complete
      
      # Shutdown
      shutdown -h now
    '';
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
  };
  
  # Include nix-me configuration on the ISO
  isoImage.contents = [
    {
      source = "$NIX_ME_DIR";
      target = "/nix-me";
    }
  ];
}
EOF
}

# Build custom installation ISO with auto-install
build_custom_iso() {
    local vm_name="$1"
    local vm_dir="$2"
    local arch="$3"
    
    log "Building custom installation ISO with auto-install..."
    
    create_autoinstall_config "$vm_name" "$vm_dir"
    
    # Build the custom ISO using nixos-generators
    cd "$NIX_ME_DIR"
    
    if command -v nix >/dev/null; then
        # Try to build custom ISO (this might fail due to cross-compilation)
        if nix build --impure --expr "
          let
            system = \"$arch-linux\";
            pkgs = import <nixpkgs> { inherit system; };
          in
          (import <nixpkgs/nixos> {
            inherit system;
            configuration = $vm_dir/autoinstall.nix;
          }).config.system.build.isoImage
        " --out-link "$vm_dir/custom-iso" 2>/dev/null; then
            echo "$vm_dir/custom-iso/iso/"*.iso
            return 0
        fi
    fi
    
    # Fallback: use standard ISO and manual setup
    warn "Custom ISO build failed, using standard ISO with setup script"
    download_iso "$arch"
}

# Create VM using UTM
create_utm_vm() {
    local vm_name="$1"
    local vm_dir="$2"
    local arch="$3"
    local iso_path="$4"
    
    log "Creating UTM VM: $vm_name"
    
    # Detect optimal VM settings
    local total_memory_gb
    total_memory_gb=$(( $(sysctl -n hw.memsize) / 1024 / 1024 / 1024 ))
    local vm_memory_mb=4096
    local cpu_cores=4
    
    if [[ $total_memory_gb -gt 16 ]]; then
        vm_memory_mb=8192
        cpu_cores=6
    elif [[ $total_memory_gb -gt 8 ]]; then
        vm_memory_mb=6144
        cpu_cores=4
    fi
    
    log "VM specs: ${vm_memory_mb}MB RAM, ${cpu_cores} CPU cores"
    
    # Create UTM bundle directory
    local utm_bundle="$vm_dir/$vm_name.utm"
    mkdir -p "$utm_bundle/Data"
    
    # Create virtual disk
    qemu-img create -f qcow2 "$utm_bundle/Data/disk-0.qcow2" 60G
    
    # Create UTM configuration
    cat > "$utm_bundle/config.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Backend</key>
    <string>qemu</string>
    <key>ConfigurationVersion</key>
    <integer>4</integer>
    <key>Information</key>
    <dict>
        <key>Name</key>
        <string>$vm_name</string>
        <key>Notes</key>
        <string>Automated NixOS development environment from nix-me</string>
    </dict>
    <key>System</key>
    <dict>
        <key>Architecture</key>
        <string>$arch</string>
        <key>Memory</key>
        <integer>$vm_memory_mb</integer>
        <key>CPU</key>
        <integer>$cpu_cores</integer>
        <key>BootUEFI</key>
        <true/>
    </dict>
    <key>Drives</key>
    <array>
        <dict>
            <key>ImagePath</key>
            <string>disk-0.qcow2</string>
            <key>Interface</key>
            <string>virtio</string>
            <key>Removable</key>
            <false/>
        </dict>
        <dict>
            <key>ImagePath</key>
            <string>$iso_path</string>
            <key>Interface</key>
            <string>usb</string>
            <key>Removable</key>
            <true/>
        </dict>
    </array>
    <key>Networking</key>
    <array>
        <dict>
            <key>Mode</key>
            <string>Shared</string>
        </dict>
    </array>
    <key>Sound</key>
    <dict>
        <key>Enabled</key>
        <true/>
    </dict>
    <key>Display</key>
    <dict>
        <key>Resolution</key>
        <dict>
            <key>Width</key>
            <integer>1920</integer>
            <key>Height</key>
            <integer>1080</integer>
        </dict>
    </dict>
</dict>
</plist>
EOF
    
    success "UTM VM created: $utm_bundle"
    echo "$utm_bundle"
}

# Create VM using QEMU directly
create_qemu_vm() {
    local vm_name="$1"
    local vm_dir="$2"
    local arch="$3"
    local iso_path="$4"
    
    log "Creating QEMU VM: $vm_name"
    
    # Create virtual disk
    qemu-img create -f qcow2 "$vm_dir/disk.qcow2" 60G
    
    # Create startup script
    cat > "$vm_dir/start.sh" << EOF
#!/bin/bash
qemu-system-$arch \\
    -M virt,accel=hvf \\
    -cpu host \\
    -smp 4 \\
    -m 4096 \\
    -drive file=disk.qcow2,format=qcow2,if=virtio \\
    -cdrom "$iso_path" \\
    -boot d \\
    -netdev user,id=net0 \\
    -device virtio-net-pci,netdev=net0 \\
    -device virtio-gpu-pci \\
    -display cocoa \\
    "\$@"
EOF
    
    chmod +x "$vm_dir/start.sh"
    success "QEMU VM created with startup script"
}

# Main VM creation function
vm_create() {
    local vm_name="${1:-}"
    local arch
    local vm_dir
    local iso_path
    local vm_path
    
    if [[ -z "$vm_name" ]]; then
        error "VM name is required. Usage: vm-manager create <vm-name>"
    fi
    
    # Validate VM name
    if [[ ! "$vm_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        error "Invalid VM name. Use only letters, numbers, hyphens, and underscores."
    fi
    
    arch=$(detect_arch)
    vm_dir="$VM_BASE_DIR/$vm_name"
    
    header "Creating VM: $vm_name ($arch)"
    
    # Check if VM already exists
    if [[ -d "$vm_dir" ]]; then
        error "VM '$vm_name' already exists. Use a different name or delete the existing VM."
    fi
    
    # Check dependencies and install if needed
    if ! check_dependencies 2>/dev/null; then
        install_dependencies
    fi
    
    # Create VM directory
    mkdir -p "$vm_dir"
    
    # Download ISO
    iso_path=$(download_iso "$arch")
    
    # Try to build custom ISO, fallback to standard
    custom_iso=$(build_custom_iso "$vm_name" "$vm_dir" "$arch" || echo "")
    if [[ -n "$custom_iso" && -f "$custom_iso" ]]; then
        iso_path="$custom_iso"
        log "Using custom auto-install ISO"
    else
        log "Using standard NixOS ISO"
    fi
    
    # Create VM based on platform
    if [[ "$(uname -s)" == "Darwin" ]] && command -v utm >/dev/null; then
        vm_path=$(create_utm_vm "$vm_name" "$vm_dir" "$arch" "$iso_path")
    else
        create_qemu_vm "$vm_name" "$vm_dir" "$arch" "$iso_path"
        vm_path="$vm_dir"
    fi
    
    # Save VM state
    set_vm_state "$vm_name" "$(jq -n \
        --arg name "$vm_name" \
        --arg arch "$arch" \
        --arg dir "$vm_dir" \
        --arg path "$vm_path" \
        --arg iso "$iso_path" \
        --arg created "$(date -Iseconds)" \
        '{
            name: $name,
            architecture: $arch,
            directory: $dir,
            vm_path: $path,
            iso_path: $iso,
            created: $created,
            status: "created"
        }')"
    
    # Create helpful documentation
    cat > "$vm_dir/README.md" << EOF
# VM: $vm_name

Created: $(date)
Architecture: $arch

## Usage
\`\`\`bash
vm-manager start $vm_name     # Start the VM
vm-manager stop $vm_name      # Stop the VM
vm-manager delete $vm_name    # Delete the VM
\`\`\`

## VM Details
- Memory: Auto-detected optimal amount
- CPU: Auto-detected optimal cores
- Disk: 60GB
- ISO: $iso_path

## First Boot
1. VM will boot from NixOS ISO
2. If using custom ISO: installation is automated
3. If using standard ISO: follow NixOS installation guide
4. VM includes nix-me configuration ready to use

## Login (after installation)
- Username: dev
- Password: dev (change after first login)
- Window Manager: i3 (select at login)
- Terminal: Super+Return opens Ghostty
EOF
    
    success "VM '$vm_name' created successfully!"
    log "Location: $vm_dir"
    log "Documentation: $vm_dir/README.md"
    
    # Offer to start the VM
    echo
    read -p "Start the VM now? [Y/n]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        vm_start "$vm_name"
    fi
}

# Start VM
vm_start() {
    local vm_name="${1:-}"
    local vm_state
    local vm_path
    
    if [[ -z "$vm_name" ]]; then
        error "VM name is required. Usage: vm-manager start <vm-name>"
    fi
    
    vm_state=$(get_vm_state "$vm_name")
    if [[ -z "$vm_state" ]]; then
        error "VM '$vm_name' not found. Create it first with: vm-manager create $vm_name"
    fi
    
    vm_path=$(echo "$vm_state" | jq -r '.vm_path')
    
    log "Starting VM: $vm_name"
    
    if [[ "$(uname -s)" == "Darwin" ]] && [[ "$vm_path" == *.utm ]]; then
        open -a UTM "$vm_path"
        success "VM started in UTM"
    elif [[ -f "$vm_path/start.sh" ]]; then
        cd "$vm_path"
        ./start.sh &
        success "VM started with QEMU"
    else
        error "Cannot start VM: No suitable startup method found"
    fi
    
    # Update state
    local updated_state
    updated_state=$(echo "$vm_state" | jq '.status = "running" | .last_started = now | strftime("%Y-%m-%dT%H:%M:%S%z")')
    set_vm_state "$vm_name" "$updated_state"
}

# List VMs
vm_list() {
    header "nix-me Virtual Machines"
    
    init_state
    local vms
    vms=$(list_vms)
    
    if [[ -z "$vms" ]]; then
        echo "No VMs found."
        echo "Create one with: vm-manager create <vm-name>"
        return 0
    fi
    
    printf "%-20s %-12s %-15s %-20s\n" "NAME" "ARCH" "STATUS" "CREATED"
    printf "%-20s %-12s %-15s %-20s\n" "----" "----" "------" "-------"
    
    while IFS= read -r vm_name; do
        local vm_state
        vm_state=$(get_vm_state "$vm_name")
        
        local arch status created
        arch=$(echo "$vm_state" | jq -r '.architecture')
        status=$(echo "$vm_state" | jq -r '.status')
        created=$(echo "$vm_state" | jq -r '.created' | cut -d'T' -f1)
        
        printf "%-20s %-12s %-15s %-20s\n" "$vm_name" "$arch" "$status" "$created"
    done <<< "$vms"
}

# Delete VM
vm_delete() {
    local vm_name="${1:-}"
    local vm_state
    local vm_dir
    
    if [[ -z "$vm_name" ]]; then
        error "VM name is required. Usage: vm-manager delete <vm-name>"
    fi
    
    vm_state=$(get_vm_state "$vm_name")
    if [[ -z "$vm_state" ]]; then
        error "VM '$vm_name' not found"
    fi
    
    vm_dir=$(echo "$vm_state" | jq -r '.directory')
    
    echo -e "${RED}This will permanently delete VM '$vm_name' and all its data.${NC}"
    echo "Location: $vm_dir"
    read -p "Type 'DELETE' to confirm: " -r
    
    if [[ "$REPLY" == "DELETE" ]]; then
        header "Deleting VM: $vm_name"
        
        # Remove VM directory
        if [[ -d "$vm_dir" ]]; then
            rm -rf "$vm_dir"
            log "VM directory removed"
        fi
        
        # Remove from state
        local tmp_file
        tmp_file=$(mktemp)
        jq "del(.vms[\"$vm_name\"])" "$STATE_FILE" > "$tmp_file"
        mv "$tmp_file" "$STATE_FILE"
        
        success "VM '$vm_name' deleted"
    else
        log "VM deletion cancelled"
    fi
}

# Show help
show_help() {
    cat << 'EOF'
nix-me VM Manager - Fully Automated Virtual Machine Management

USAGE:
    vm-manager <COMMAND> [VM_NAME]

COMMANDS:
    create <name>    Create a new VM with specified name
    start <name>     Start an existing VM
    list             List all VMs
    delete <name>    Delete a VM permanently
    help             Show this help

EXAMPLES:
    vm-manager create dev-environment
    vm-manager create client-project-alpha
    vm-manager start dev-environment
    vm-manager list
    vm-manager delete old-project

FEATURES:
    ✅ Fully automated VM creation
    ✅ Custom VM naming
    ✅ Automatic ISO download
    ✅ Auto-detected optimal settings
    ✅ Integration with your nix-me configuration
    ✅ Cross-platform (macOS with UTM, Linux with QEMU)

Each VM gets your complete nix-me development environment:
- NixOS with i3 window manager
- Ghostty terminal with your exact configuration
- Neovim with your plugins and settings
- All your development tools and aliases

VMs are stored in: ~/.local/share/nix-me/vms/
EOF
}

# Main command dispatcher
main() {
    init_state
    
    local command="${1:-help}"
    shift || true
    
    case "$command" in
        create)   vm_create "$@" ;;
        start)    vm_start "$@" ;;
        list)     vm_list ;;
        delete)   vm_delete "$@" ;;
        help|-h|--help) show_help ;;
        *) 
            error "Unknown command: $command. Use 'vm-manager help' for usage."
            ;;
    esac
}

main "$@"