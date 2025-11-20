# Omarchy VM Guide

Create VMs with DHH's [Omarchy](https://omarchy.org/) - Arch Linux with Hyprland tiling window manager. Optionally layer your nix-me configurations (Fish shell, kubectl, k3d, etc.) on top.

## Overview

**Omarchy** (by DHH) provides:

- **Base**: Arch Linux
- **Desktop**: Hyprland tiling window manager
- **Editor**: Neovim
- **Terminal**: Alacritty
- **Browser**: Chromium
- **Shell**: Zsh (default)
- **Package Manager**: pacman

**nix-me additions** (optional):

- **Shell**: Fish with starship prompt, fzf, zoxide
- **Kubernetes**: kubectl, k3d, helm
- **Git**: gh CLI, lazygit, delta
- **CLI tools**: bat, eza, ripgrep, fd
- **Configs**: tmux, direnv, git

## Quick Start

```bash
# 1. Download Omarchy ISO (opens browser)
make omarchy-iso

# 2. Create VM setup instructions
make omarchy-create

# 3. Follow generated README to create UTM VM and install Omarchy
```

## VM Creation

### Using Make

```bash
# Default VM (8GB RAM, 4 CPUs, 80GB disk)
make omarchy-create

# Custom specs
make omarchy-create name=mydev mem=16384 cpu=8 disk=120G

# List configurations
make omarchy-list

# Validate configuration
make omarchy-build
```

### Using Script Directly

```bash
# Download ISO
./scripts/omarchy-vm.sh download-iso

# Create VM
./scripts/omarchy-vm.sh create mydev 8192 4 80G

# Help
./scripts/omarchy-vm.sh help
```

## Installation Process

1. **Create VM in UTM** (manual step)
   - Follow instructions in generated README
   - Use Omarchy ISO
   - Configure VM specs (8GB+ RAM recommended)

2. **Install Omarchy**
   - Boot from ISO
   - Follow the Omarchy installer (automated)
   - Set up user account
   - Reboot into installed system

3. **Apply nix-me Configuration** (optional)
   ```bash
   # Install Nix package manager
   curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install

   # Source Nix
   . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh

   # Clone nix-me repo
   git clone https://github.com/lucamaraschi/nix-me.git ~/.config/nixpkgs
   cd ~/.config/nixpkgs

   # Apply home-manager configuration
   # For Apple Silicon VM:
   nix run home-manager/master -- switch --flake .#omarchy-aarch64

   # For x86_64 VM:
   # nix run home-manager/master -- switch --flake .#omarchy
   ```

## Default Setup

Omarchy comes with its own user setup during installation.

After applying nix-me configs:
- **Shell**: Fish available (run `chsh -s $(which fish)` to switch)
- **Tools**: kubectl, k3d, helm, gh, lazygit, etc. via Nix

## Shared Configuration

The nix-me configs use shared modules that work across macOS and Linux:

### Cross-Platform Modules

- `modules/shared/packages.nix` - Common CLI tools (kubectl, k3d, helm, etc.)
- `modules/shared/fish-base.nix` - Base Fish shell config
- `modules/home-manager/apps/git.nix` - Git configuration
- `modules/home-manager/apps/tmux.nix` - Tmux configuration
- `modules/home-manager/shell/direnv.nix` - Direnv setup

### Omarchy-Specific

- `home-configurations/omarchy.nix` - Standalone home-manager for Arch Linux
- `modules/nixos/fish.nix` - Linux-specific Fish aliases (pacman, systemctl)

## Customization

### Add Packages via Nix

Edit `modules/shared/packages.nix`:

```nix
commonPackages = with pkgs; [
  # Add your tools here
  your-tool
];
```

### Modify Fish Shell

For cross-platform changes, edit `modules/shared/fish-base.nix`.

For Linux/Arch-only changes, edit `home-configurations/omarchy.nix`.

### Hyprland Configuration

Omarchy manages Hyprland config at `~/.config/hypr/hyprland.conf`.

nix-me adds optional additions at `~/.config/hypr/nix-me.conf`.
You can source it in your main config:

```conf
source = ~/.config/hypr/nix-me.conf
```

### Alacritty Configuration

Omarchy manages Alacritty at `~/.config/alacritty/alacritty.toml`.

nix-me adds Fish shell config at `~/.config/alacritty/nix-me.toml`.

## Keyboard Shortcuts

### Hyprland (Omarchy defaults)

- `Super + Enter` - Open terminal (Alacritty)
- `Super + Q` - Close window
- `Super + D` - Application launcher
- `Super + 1-9` - Switch workspace
- `Super + Shift + 1-9` - Move window to workspace
- `Super + Arrow keys` - Navigate windows
- `Super + F` - Toggle fullscreen

### Fish Shell Aliases (nix-me)

- `update` - Update Arch (`sudo pacman -Syu`)
- `k` - kubectl
- `d` - docker
- `g` - git
- `ll` - eza -la
- `cat` - bat
- `find` - fd
- `grep` - rg

## Architecture

```
flake.nix
└── homeConfigurations
    ├── omarchy (x86_64-linux)
    └── omarchy-aarch64 (Apple Silicon VMs)
        └── home-configurations/omarchy.nix
            ├── modules/shared/packages.nix (CLI tools)
            ├── modules/nixos/fish.nix
            │   └── modules/shared/fish-base.nix
            ├── modules/home-manager/apps/git.nix
            ├── modules/home-manager/apps/tmux.nix
            └── modules/home-manager/shell/direnv.nix
```

## Troubleshooting

### Nix not found after install

- Source the Nix profile: `. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh`
- Or restart your shell/terminal

### Fish shell not loading

- Install Fish: `sudo pacman -S fish`
- Set as default: `chsh -s $(which fish)`
- Ensure it's in /etc/shells

### home-manager command not found

- Run via nix: `nix run home-manager/master -- switch --flake .#omarchy-aarch64`

### Hyprland not starting

- Check GPU drivers: `pacman -Qs nvidia` or `pacman -Qs mesa`
- View logs: `journalctl -xe`

### Network not working

- Check NetworkManager: `sudo systemctl status NetworkManager`
- Restart: `sudo systemctl restart NetworkManager`

### Clipboard sharing in UTM

```bash
sudo pacman -S spice-vdagent
sudo systemctl enable --now spice-vdagentd
```

## Related Documentation

- [Omarchy Official Manual](https://learn.omacom.io/2/the-omarchy-manual)
- [VM Testing Guide](./VM_TESTING.md)
- [Quick Reference](./QUICK_REFERENCE.md)
