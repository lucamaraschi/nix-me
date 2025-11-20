#!/usr/bin/env bash
# Omarchy VM Manager - Create Arch Linux VMs with DHH's Omarchy (Hyprland)
# Optionally layer nix-me configurations (Fish, kubectl, k3d, etc.) on top
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
VM_DATA_DIR="$HOME/.local/share/nix-me/omarchy-vms"
OMARCHY_VERSION="3.1"
OMARCHY_ISO_NAME="omarchy-${OMARCHY_VERSION}.iso"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Initialize directories
init_directories() {
    mkdir -p "$VM_DATA_DIR/isos"
    mkdir -p "$VM_DATA_DIR/configs"
}

# Download Omarchy ISO
download_iso() {
    local iso_path="$VM_DATA_DIR/isos/$OMARCHY_ISO_NAME"

    if [[ -f "$iso_path" ]]; then
        log_info "Omarchy ISO already downloaded: $iso_path"
        return 0
    fi

    log_info "Downloading Omarchy ${OMARCHY_VERSION} ISO..."
    log_warn "Omarchy ISO must be downloaded from: https://omarchy.org/"
    log_info ""
    log_info "Please:"
    log_info "  1. Visit https://omarchy.org/"
    log_info "  2. Download the ISO (click 'Download the ISO')"
    log_info "  3. Move the downloaded file to:"
    log_info "     ${CYAN}$iso_path${NC}"
    log_info ""
    log_info "After downloading, run this command again to verify."

    # Create placeholder directory
    mkdir -p "$VM_DATA_DIR/isos"

    # Open the download page
    if command -v open &>/dev/null; then
        read -p "Open omarchy.org in browser? [Y/n] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            open "https://omarchy.org/"
        fi
    fi

    return 1
}

# Create UTM VM
create_vm() {
    local vm_name="${1:-omarchy-dev}"
    local memory="${2:-8192}"  # 8GB default
    local cpus="${3:-4}"
    local disk_size="${4:-80G}"  # 80GB default for full dev env

    log_info "Creating Omarchy VM: $vm_name"
    log_info "  Memory: ${memory}MB"
    log_info "  CPUs: $cpus"
    log_info "  Disk: $disk_size"

    # Check if UTM is installed
    if ! command -v /Applications/UTM.app/Contents/MacOS/utmctl &>/dev/null; then
        log_error "UTM not found. Please install UTM first."
        return 1
    fi

    local iso_path="$VM_DATA_DIR/isos/$NIXOS_ISO_NAME"
    if [[ ! -f "$iso_path" ]]; then
        log_error "ISO not found. Run: $0 download-iso"
        return 1
    fi

    # Create VM config directory
    local vm_config_dir="$VM_DATA_DIR/configs/$vm_name"
    mkdir -p "$vm_config_dir"

    # Generate VM creation instructions
    cat > "$vm_config_dir/README.md" << EOF
# Omarchy VM: $vm_name

Arch Linux with Hyprland tiling window manager by DHH.

## Step 1: UTM VM Creation

1. Open UTM
2. Click "Create a New Virtual Machine"
3. Select "Virtualize" (Apple Silicon)
4. Select "Linux"
5. Click "Browse" and select:
   \`$iso_path\`
6. Configure:
   - Memory: ${memory}MB (minimum 8192MB recommended)
   - CPU Cores: $cpus
7. Storage: $disk_size
8. Continue with defaults, name the VM: "$vm_name"
9. Before starting, go to VM Settings:
   - Display: Enable "Retina Mode" for crisp fonts
   - Network: Shared Network
10. Start the VM

## Step 2: Install Omarchy

The Omarchy ISO is a live installer. Follow the on-screen instructions:

1. Boot from ISO
2. Follow the Omarchy installer
3. Set up user account and password
4. Let it install (2-10 minutes)
5. Reboot into installed system

## Step 3: Apply nix-me Configuration (Optional)

After Omarchy is installed, you can layer your nix-me configurations on top:

\`\`\`bash
# 1. Install Nix package manager on Arch
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install

# 2. Restart shell or source nix
. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh

# 3. Clone nix-me repository
git clone https://github.com/lucamaraschi/nix-me.git ~/.config/nixpkgs
cd ~/.config/nixpkgs

# 4. Apply home-manager configuration (for aarch64/Apple Silicon VM)
nix run home-manager/master -- switch --flake .#omarchy-aarch64

# Or for x86_64 VM:
# nix run home-manager/master -- switch --flake .#omarchy
\`\`\`

This will add:
- Fish shell with your custom aliases and functions
- Git configuration
- Tmux setup
- Starship prompt
- Additional CLI tools (kubectl, k3d, etc.)

Note: Omarchy already includes Neovim, Alacritty, and many dev tools.
Your nix-me config will complement (not replace) the Omarchy setup.

## Omarchy Features

- **Desktop**: Hyprland tiling window manager
- **Terminal**: Alacritty
- **Editor**: Neovim
- **Browser**: Chromium
- **Shell**: Zsh (default, but Fish available via nix-me)
- **Package Manager**: pacman (Arch Linux)

### Key Bindings (Hyprland)

- \`Super + Enter\` - Open terminal
- \`Super + Q\` - Close window
- \`Super + D\` - Application launcher
- \`Super + 1-9\` - Switch workspace
- \`Super + Shift + 1-9\` - Move window to workspace
- \`Super + Arrow keys\` - Navigate windows
- \`Super + F\` - Toggle fullscreen

## UTM Tips for Omarchy

1. **Clipboard sharing**: Install spice-vdagent
   \`\`\`bash
   sudo pacman -S spice-vdagent
   sudo systemctl enable spice-vdagentd
   \`\`\`

2. **Shared folders**: UTM supports shared directories via SPICE

3. **Resolution**: Hyprland auto-detects, but you can adjust in ~/.config/hypr/hyprland.conf

4. **Audio**: Should work out of the box with PipeWire

Enjoy your Omarchy VM!
EOF

    log_success "VM configuration created at $vm_config_dir"
    log_info "Follow instructions in: $vm_config_dir/README.md"

    # Open README
    if command -v open &>/dev/null; then
        open "$vm_config_dir/README.md"
    fi
}

# List available configurations
list_configs() {
    log_info "Available Omarchy VM configurations:"

    if [[ -d "$VM_DATA_DIR/configs" ]]; then
        for config in "$VM_DATA_DIR/configs"/*; do
            if [[ -d "$config" ]]; then
                local name=$(basename "$config")
                echo "  - $name"
            fi
        done
    else
        echo "  (none)"
    fi
}

# Validate home-manager configuration
build_config() {
    log_info "Validating Omarchy home-manager configuration..."

    # Check if flake is valid
    if ! nix --extra-experimental-features "nix-command flakes" flake check "$PROJECT_ROOT" 2>&1 | head -30; then
        log_error "Flake check failed. Fix errors first."
        return 1
    fi

    log_success "Configuration validated successfully"
    log_info ""
    log_info "Available home-manager configurations:"
    echo "  - omarchy          (x86_64-linux)"
    echo "  - omarchy-aarch64  (aarch64-linux, for Apple Silicon VMs)"
    log_info ""
    log_info "To apply inside Omarchy VM:"
    echo ""
    echo "  # For Apple Silicon VM:"
    echo "  nix run home-manager/master -- switch --flake $PROJECT_ROOT#omarchy-aarch64"
    echo ""
    echo "  # For x86_64 VM:"
    echo "  nix run home-manager/master -- switch --flake $PROJECT_ROOT#omarchy"
    echo ""
}

# Show help
show_help() {
    cat << EOF
${CYAN}Omarchy VM Manager${NC}

Create Arch Linux VMs with DHH's Omarchy (Hyprland tiling WM).
Optionally layer nix-me configs (Fish, kubectl, k3d) on top.

${YELLOW}Usage:${NC}
  $0 <command> [options]

${YELLOW}Commands:${NC}
  download-iso              Download Omarchy ISO (opens browser)
  create [name] [mem] [cpu] [disk]
                           Create new VM setup
                           Defaults: name=omarchy-dev, mem=8192MB, cpu=4, disk=80G
  list                     List VM configurations
  build                    Validate home-manager configuration
  help                     Show this help

${YELLOW}Examples:${NC}
  $0 download-iso                     # Get Omarchy ISO
  $0 create                           # Create default VM
  $0 create mydev 16384 8 120G       # Custom specs
  $0 build                            # Validate configuration

${YELLOW}Omarchy Features:${NC}
  - Arch Linux base
  - Hyprland tiling window manager
  - Neovim, Alacritty, Chromium
  - Modern dev environment by DHH

${YELLOW}nix-me Additions (optional):${NC}
  - Fish shell with starship prompt
  - Kubernetes tools (kubectl, k3d, helm)
  - Additional CLI tools (bat, eza, fzf, ripgrep)
  - Git configuration, tmux, direnv

${YELLOW}Files:${NC}
  ISOs:    $VM_DATA_DIR/isos/
  Configs: $VM_DATA_DIR/configs/

EOF
}

# Main
main() {
    init_directories

    local command="${1:-help}"

    case "$command" in
        download-iso)
            download_iso
            ;;
        create)
            shift
            create_vm "$@"
            ;;
        list)
            list_configs
            ;;
        build)
            shift
            build_config "$@"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
