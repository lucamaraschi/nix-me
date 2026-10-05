# Enhanced VM manager supporting multiple VM types including Omarchy
{ config, lib, pkgs, username, ... }:

let
  # VM type configurations
  vmTypes = {
    nix = {
      name = "nix-darwin-vm";
      description = "NixOS development VM";
      isoUrl = "https://channels.nixos.org/nixos-23.11/latest-nixos-minimal-x86_64-linux.iso";
      setupScript = ''
        # NixOS VM setup
        echo "🚀 Setting up NixOS development environment..."

        # Basic NixOS configuration
        sudo mkdir -p /etc/nixos
        sudo tee /etc/nixos/configuration.nix > /dev/null << 'EOL'
{ config, pkgs, ... }: {
  imports = [ ./hardware-configuration.nix ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "nixos-vm";
  networking.networkmanager.enable = true;

  users.users.${username} = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
    packages = with pkgs; [ firefox tree ];
  };

  environment.systemPackages = with pkgs; [
    vim git curl wget
  ];

  services.openssh.enable = true;
  system.stateVersion = "23.11";
}
EOL

        echo "✅ NixOS VM setup complete!"
      '';
    };

    omarchy = {
      name = "omarchy-dev";
      description = "Omarchy 2.0 development VM with custom dotfiles";
      isoUrl = "https://github.com/basecamp/omakub/releases/download/v2.0.0/omakub-2.0.iso";
      setupScript = ''
        #!/bin/bash
        # Omarchy VM Dotfiles Setup Script
        set -e

        echo "🚀 Setting up Omarchy VM with custom dotfiles..."

        # Install git if not present
        sudo apt update
        sudo apt install -y git curl jq

        # Clone your dotfiles
        if [ ! -d "$HOME/.dotfiles" ]; then
            echo "📦 Cloning dotfiles repository..."
            git clone "${config.vmManager.dotfilesRepo}" "$HOME/.dotfiles"
        fi

        cd "$HOME/.dotfiles"

        # Create symlinks for common dotfiles
        echo "🔗 Creating symlinks..."
        [ -f ".vimrc" ] && ln -sf "$HOME/.dotfiles/.vimrc" "$HOME/.vimrc"
        [ -f ".tmux.conf" ] && ln -sf "$HOME/.dotfiles/.tmux.conf" "$HOME/.tmux.conf"
        [ -f ".gitconfig" ] && ln -sf "$HOME/.dotfiles/.gitconfig" "$HOME/.gitconfig"
        [ -d ".config" ] && ln -sf "$HOME/.dotfiles/.config" "$HOME/.config"

        # Install Vim plugins if using Vim-Plug
        if [ -f "$HOME/.vimrc" ] && grep -q "vim-plug" "$HOME/.vimrc"; then
            echo "📝 Installing Vim plugins..."
            curl -fLo ~/.vim/autoload/plug.vim --create-dirs \
                https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
            vim +PlugInstall +qall || true
        fi

        # Install Neovim config if present
        if [ -d ".config/nvim" ]; then
            echo "⚡ Setting up Neovim configuration..."
            mkdir -p "$HOME/.config"
            ln -sf "$HOME/.dotfiles/.config/nvim" "$HOME/.config/nvim"
        fi

        # Set up Fish shell if config present
        if [ -d ".config/fish" ]; then
            echo "🐟 Setting up Fish shell..."
            sudo apt install -y fish
            mkdir -p "$HOME/.config"
            ln -sf "$HOME/.dotfiles/.config/fish" "$HOME/.config/fish"

            # Set Fish as default shell
            echo "$(which fish)" | sudo tee -a /etc/shells
            chsh -s "$(which fish)" || true
        fi

        # Install development tools
        echo "🛠️  Installing development tools..."
        sudo apt install -y \
            build-essential \
            vim \
            tmux \
            ripgrep \
            fd-find \
            bat \
            htop \
            tree \
            nodejs \
            npm

        # Install Rust
        if ! command -v cargo >/dev/null; then
            echo "🦀 Installing Rust..."
            curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
            source ~/.cargo/env || true
        fi

        # Install modern CLI tools
        if command -v cargo >/dev/null; then
            echo "⚡ Installing modern CLI tools..."
            cargo install exa bat ripgrep fd-find || true
        fi

        # Install Starship prompt
        if ! command -v starship >/dev/null; then
            echo "🚀 Installing Starship prompt..."
            curl -sS https://starship.rs/install.sh | sh -s -- -y || true
        fi

        # Run custom setup script if present
        if [ -f "setup.sh" ]; then
            echo "⚙️  Running custom setup script..."
            chmod +x setup.sh
            ./setup.sh || true
        fi

        echo "✅ Omarchy VM setup complete!"
        echo "🔄 You may need to restart your terminal for all changes to take effect."
      '';
    };

    ubuntu = {
      name = "ubuntu-dev";
      description = "Ubuntu development VM";
      isoUrl = "https://releases.ubuntu.com/22.04/ubuntu-22.04.3-desktop-amd64.iso";
      setupScript = ''
        echo "🚀 Setting up Ubuntu development environment..."

        # Update system
        sudo apt update && sudo apt upgrade -y

        # Install development tools
        sudo apt install -y \
            build-essential \
            git \
            vim \
            curl \
            wget \
            tmux \
            fish \
            nodejs \
            npm

        echo "✅ Ubuntu VM setup complete!"
      '';
    };
  };

  # Enhanced VM management script
  vmManagerScript = pkgs.writeShellScriptBin "vm" ''
    #!/bin/bash
    set -e

    # Configuration
    VM_DIR="$HOME/.local/share/vms"

    # Colors for output
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color

    log() {
        echo -e "''${GREEN}[$(date '+%H:%M:%S')]''${NC} $1"
    }

    warn() {
        echo -e "''${YELLOW}[$(date '+%H:%M:%S')] WARNING:''${NC} $1"
    }

    error() {
        echo -e "''${RED}[$(date '+%H:%M:%S')] ERROR:''${NC} $1"
    }

    info() {
        echo -e "''${BLUE}[$(date '+%H:%M:%S')] INFO:''${NC} $1"
    }

    # Function to check if UTM is installed
    check_utm() {
        if ! command -v utm >/dev/null 2>&1 && ! [ -d "/Applications/UTM.app" ]; then
            error "UTM is not installed. Please install it via Homebrew or from the App Store."
            echo "  brew install --cask utm"
            exit 1
        fi
    }

    # Function to get VM type configuration
    get_vm_config() {
        local vm_type="$1"
        case "$vm_type" in
            nix)
                VM_NAME="${vmTypes.nix.name}"
                VM_DESCRIPTION="${vmTypes.nix.description}"
                ISO_URL="${vmTypes.nix.isoUrl}"
                SETUP_SCRIPT='${vmTypes.nix.setupScript}'
                ;;
            omarchy)
                VM_NAME="${vmTypes.omarchy.name}"
                VM_DESCRIPTION="${vmTypes.omarchy.description}"
                ISO_URL="${vmTypes.omarchy.isoUrl}"
                SETUP_SCRIPT='${vmTypes.omarchy.setupScript}'
                ;;
            ubuntu)
                VM_NAME="${vmTypes.ubuntu.name}"
                VM_DESCRIPTION="${vmTypes.ubuntu.description}"
                ISO_URL="${vmTypes.ubuntu.isoUrl}"
                SETUP_SCRIPT='${vmTypes.ubuntu.setupScript}'
                ;;
            *)
                error "Unknown VM type: $vm_type"
                echo "Available types: nix, omarchy, ubuntu"
                exit 1
                ;;
        esac
    }

    # Function to download ISO
    download_iso() {
        local vm_type="$1"
        local iso_path="$VM_DIR/$vm_type.iso"

        if [ -f "$iso_path" ]; then
            info "ISO for $vm_type already exists at $iso_path"
            return 0
        fi

        log "Downloading $vm_type ISO..."
        mkdir -p "$VM_DIR"

        if command -v curl >/dev/null; then
            curl -L "$ISO_URL" -o "$iso_path"
        elif command -v wget >/dev/null; then
            wget "$ISO_URL" -O "$iso_path"
        else
            error "Neither curl nor wget found. Cannot download ISO."
            exit 1
        fi

        if [ ! -f "$iso_path" ]; then
            error "Failed to download ISO for $vm_type"
            exit 1
        fi

        log "ISO downloaded successfully"
    }

    # Function to create VM
    create_vm() {
        local vm_type="$1"
        local vm_name="''${2:-$VM_NAME}"
        local memory="''${3:-${config.vmManager.defaultMemory}}"
        local cpus="''${4:-${toString config.vmManager.defaultCpus}}"
        local disk="''${5:-${config.vmManager.defaultDiskSize}}"

        get_vm_config "$vm_type"
        check_utm
        download_iso "$vm_type"

        local vm_path="$VM_DIR/$vm_name"

        log "Creating $VM_DESCRIPTION..."
        mkdir -p "$vm_path"

        # Create VM configuration
        cat > "$vm_path/config.json" << EOF
{
  "name": "$vm_name",
  "type": "$vm_type",
  "description": "$VM_DESCRIPTION",
  "memory": "$memory",
  "cpus": $cpus,
  "disk_size": "$disk",
  "iso_path": "$VM_DIR/$vm_type.iso",
  "created": "$(date -Iseconds)",
  "dotfiles_repo": "${config.vmManager.dotfilesRepo}"
}
EOF

        # Create setup script
        cat > "$vm_path/setup.sh" << 'EOF'
$SETUP_SCRIPT
EOF
        chmod +x "$vm_path/setup.sh"

        # Create UTM configuration
        cat > "$vm_path/utm-config.json" << EOF
{
  "name": "$vm_name",
  "architecture": "x86_64",
  "memory": $(echo "$memory" | sed 's/G//' | awk '{print $1 * 1024}'),
  "cpus": $cpus,
  "drives": [
    {
      "type": "disk",
      "size": "$disk",
      "interface": "sata"
    },
    {
      "type": "cdrom",
      "path": "$VM_DIR/$vm_type.iso",
      "interface": "sata"
    }
  ],
  "network": {
    "type": "NAT"
  },
  "display": {
    "type": "VGA"
  }
}
EOF

        log "VM '$vm_name' ($vm_type) created successfully!"
        log "VM directory: $vm_path"

        info "Next steps:"
        echo "  1. Start the VM: vm start $vm_name"
        echo "  2. Install the OS in the VM"
        echo "  3. After installation, run the setup script:"
        echo "     bash $vm_path/setup.sh"
    }

    # Function to start VM
    start_vm() {
        local vm_name="$1"

        if [ -z "$vm_name" ]; then
            error "VM name required. Usage: vm start <vm-name>"
            exit 1
        fi

        local vm_path="$VM_DIR/$vm_name"

        if [ ! -d "$vm_path" ]; then
            error "VM '$vm_name' not found. Available VMs:"
            list_vms
            exit 1
        fi

        log "Starting VM '$vm_name'..."

        # Try to start with UTM CLI if available
        if command -v utm >/dev/null 2>&1; then
            utm start "$vm_name" || {
                warn "UTM CLI failed, opening UTM app..."
                open -a UTM
            }
        else
            log "Opening UTM app..."
            open -a UTM
        fi
    }

    # Function to stop VM
    stop_vm() {
        local vm_name="$1"

        if [ -z "$vm_name" ]; then
            error "VM name required. Usage: vm stop <vm-name>"
            exit 1
        fi

        log "Stopping VM '$vm_name'..."

        if command -v utm >/dev/null 2>&1; then
            utm stop "$vm_name" || warn "Could not stop VM via CLI"
        else
            warn "UTM CLI not available. Please stop the VM manually in UTM app."
        fi
    }

    # Function to delete VM
    delete_vm() {
        local vm_name="$1"

        if [ -z "$vm_name" ]; then
            error "VM name required. Usage: vm delete <vm-name>"
            exit 1
        fi

        local vm_path="$VM_DIR/$vm_name"

        if [ ! -d "$vm_path" ]; then
            warn "VM '$vm_name' not found"
            return 0
        fi

        echo -n "Are you sure you want to delete VM '$vm_name'? (y/N): "
        read -r response

        if [[ "$response" =~ ^[Yy]$ ]]; then
            log "Deleting VM '$vm_name'..."
            rm -rf "$vm_path"
            log "VM deleted successfully"
        else
            log "Deletion cancelled"
        fi
    }

    # Function to list VMs
    list_vms() {
        log "Available VMs:"

        if [ ! -d "$VM_DIR" ]; then
            info "No VMs found. Create one with: vm create <type> [name]"
            return 0
        fi

        for vm_dir in "$VM_DIR"/*/; do
            if [ -d "$vm_dir" ]; then
                local vm_name=$(basename "$vm_dir")
                local config_file="$vm_dir/config.json"

                # Skip ISO files and other non-VM directories
                if [[ "$vm_name" == *.iso ]]; then
                    continue
                fi

                if [ -f "$config_file" ]; then
                    local vm_type=$(jq -r '.type // "unknown"' "$config_file" 2>/dev/null || echo "unknown")
                    local description=$(jq -r '.description // "unknown"' "$config_file" 2>/dev/null || echo "unknown")
                    local created=$(jq -r '.created // "unknown"' "$config_file" 2>/dev/null || echo "unknown")
                    local memory=$(jq -r '.memory // "unknown"' "$config_file" 2>/dev/null || echo "unknown")
                    local cpus=$(jq -r '.cpus // "unknown"' "$config_file" 2>/dev/null || echo "unknown")

                    echo "  📱 $vm_name ($vm_type)"
                    echo "     $description"
                    echo "     Memory: $memory, CPUs: $cpus"
                    echo "     Created: $created"
                    echo ""
                else
                    echo "  📱 $vm_name (configuration missing)"
                    echo ""
                fi
            fi
        done
    }

    # Function to show VM types
    show_types() {
        log "Available VM types:"
        echo "  🐧 nix      - ${vmTypes.nix.description}"
        echo "  🚀 omarchy  - ${vmTypes.omarchy.description}"
        echo "  🔶 ubuntu   - ${vmTypes.ubuntu.description}"
        echo ""
        echo "Usage:"
        echo "  vm create <type> [name] [memory] [cpus] [disk]"
        echo ""
        echo "Examples:"
        echo "  vm create omarchy                    # Create Omarchy VM with defaults"
        echo "  vm create omarchy my-dev-env 8G 4    # Create with custom specs"
        echo "  vm create nix nixos-test             # Create NixOS VM"
    }

    # Function to show help
    show_help() {
        echo "VM Manager - Create and manage development VMs"
        echo ""
        echo "Usage: vm <command> [options]"
        echo ""
        echo "Commands:"
        echo "  create <type> [name] [memory] [cpus] [disk]  Create a new VM"
        echo "  start <name>                                 Start a VM"
        echo "  stop <name>                                  Stop a VM"
        echo "  delete <name>                                Delete a VM"
        echo "  list                                         List all VMs"
        echo "  types                                        Show available VM types"
        echo "  help                                         Show this help message"
        echo ""
        echo "VM Types:"
        echo "  nix       NixOS development VM"
        echo "  omarchy   Omarchy 2.0 with your dotfiles"
        echo "  ubuntu    Ubuntu development VM"
        echo ""
        echo "Examples:"
        echo "  vm create omarchy                    # Create Omarchy VM with your dotfiles"
        echo "  vm create nix                        # Create NixOS VM"
        echo "  vm start omarchy-dev                 # Start the VM"
        echo "  vm list                              # List all VMs"
        echo ""
    }

    # Main command handling
    case "''${1:-help}" in
        create)
            if [ -z "$2" ]; then
                error "VM type required"
                show_types
                exit 1
            fi
            create_vm "$2" "$3" "$4" "$5" "$6"
            ;;
        start)
            start_vm "$2"
            ;;
        stop)
            stop_vm "$2"
            ;;
        delete|remove)
            delete_vm "$2"
            ;;
        list|ls)
            list_vms
            ;;
        types)
            show_types
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            error "Unknown command: $1"
            echo ""
            show_help
            exit 1
            ;;
    esac
  '';

in
{
  options.vmManager = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable VM management with support for multiple VM types";
    };

    defaultMemory = lib.mkOption {
      type = lib.types.str;
      default = "4G";
      description = "Default VM memory allocation";
    };

    defaultCpus = lib.mkOption {
      type = lib.types.int;
      default = 2;
      description = "Default number of CPU cores";
    };

    defaultDiskSize = lib.mkOption {
      type = lib.types.str;
      default = "60G";
      description = "Default VM disk size";
    };

    dotfilesRepo = lib.mkOption {
      type = lib.types.str;
      default = "https://github.com/${username}/dotfiles.git";
      description = "Git repository containing your dotfiles (used for Omarchy VMs)";
    };
  };

  config = lib.mkIf config.vmManager.enable {
    # Add the vm command to system packages
    environment.systemPackages = [
      vmManagerScript
      pkgs.jq  # For JSON parsing in scripts
    ];

    # Ensure UTM is installed
    homebrew.casks = lib.mkDefault [ "utm" ];

    # Add to Fish functions for easy access
    home-manager.users.${username} = lib.mkIf (config.programs.fish.enable or false) {
      programs.fish.functions = {
        # Quick aliases for different VM types with flag support
        vm-omarchy = {
          body = "vm create omarchy $argv";
          description = "Create Omarchy VM with your dotfiles (supports flags: -n name -m memory -c cpus -d disk)";
        };

        vm-nix = {
          body = "vm create nix $argv";
          description = "Create NixOS development VM (supports flags: -n name -m memory -c cpus -d disk)";
        };

        vm-ubuntu = {
          body = "vm create ubuntu $argv";
          description = "Create Ubuntu development VM (supports flags: -n name -m memory -c cpus -d disk)";
        };

        # Convenience functions for common configurations
        vm-dev = {
          body = "vm create omarchy --name dev-vm --memory 8G --cpus 4 --disk 100G";
          description = "Create high-spec Omarchy development VM";
        };

        vm-test = {
          body = "vm create omarchy --name test-vm --memory 4G --cpus 2 --disk 60G";
          description = "Create lightweight Omarchy VM for testing";
        };
      };
    };
  };
}
