# VM - Virtual Machine Configuration

**Type:** Base Template
**Inherits From:** `shared`
**Used By:** `vm-test`, `nixos-vm`

## Overview

This is the minimal configuration template for macOS running in virtual machines (UTM, VMware, Parallels, VirtualBox). It's optimized for fast boot times, reduced resource usage, and disables features that don't work well in virtualized environments.

## Purpose

Use this configuration for:
- Testing nix-me configurations before deploying
- Development VMs for isolated environments
- CI/CD runners in virtualized environments
- Learning Nix without affecting your main system
- Quick disposable environments

## Inheritance Chain

```
hosts/shared/default.nix  (Layer 1: Base for all machines - MODIFIED)
  ↓
hosts/vm/default.nix      (Layer 2: VM-specific optimizations)
```

## Key Features

### Minimal Package Set

Instead of inheriting ALL packages from shared, VM config overrides with minimal essentials:

**GUI Applications (Homebrew Casks):**
- Visual Studio Code (development)
- Google Chrome (browser)
- Ghostty (terminal)
- Rectangle (window manager)

**System Packages:** Inherits from shared but removes heavy packages

### System Optimizations

**Dock:**
- Icon size: 36px (moderate size)
- Other settings inherited from shared

**Finder:**
- Desktop icons: Disabled (less clutter in VM)

**Custom Preferences:**
- Completely disabled (many don't work in VMs)
- Prevents errors and warnings

```nix
system.defaults = {
  dock = {
    tilesize = lib.mkForce 36;
  };

  finder = {
    CreateDesktop = false;
  };

  # Remove problematic settings for VMs
  CustomUserPreferences = lib.mkForce {};
};
```

### Performance Optimizations

**Activation Script:**
```nix
system.activationScripts.vmOptimization.text = ''
  echo "Configuring VM optimizations..." >&2

  # Disable spotlight indexing for better VM performance
  sudo mdutil -a -i off 2>/dev/null || echo "Could not disable spotlight indexing"

  # Touch a last-rebuild file
  printf "%s" "$(date)" > "$HOME"/.nix-last-rebuild
'';
```

**What it does:**
- Disables Spotlight indexing (saves CPU and disk I/O)
- Creates rebuild timestamp for tracking
- Fails gracefully if commands don't work

### Disabled Features

- Energy management (no battery in VM)
- Mac App Store apps (iCloud doesn't work in VMs typically)
- Spotlight indexing (performance)
- Custom system preferences (often incompatible)
- Power nap, sleep modes
- Battery-related settings

## Installation in VM

### Prerequisites

1. **Create macOS VM** in UTM, VMware, Parallels, or VirtualBox
2. **Boot macOS** and complete initial setup
3. **Get your username:** `whoami`

### Installation

```bash
# In your VM, run:
curl -L https://raw.githubusercontent.com/lucamaraschi/nix-me/main/install.sh | bash

# Or with VM-specific flags:
SKIP_MAS_APPS=1 ./install.sh vm-name vm "Test VM" yourusername
```

### Environment Variables for VMs

```bash
SKIP_MAS_APPS=1          # Skip Mac App Store (iCloud doesn't work in VMs)
SKIP_BREW_ON_VM=1        # Skip Homebrew entirely (faster testing)
```

## Creating a New VM Configuration

### Option 1: Simple (use machineType in flake.nix)

```nix
"test-vm" = mkDarwinSystem {
  hostname = "test-vm";
  machineType = "vm";
  machineName = "Test VM";
  username = "yourusername";
};
```

### Option 2: Minimal Testing VM

```nix
# hosts/test-vm/default.nix
{ pkgs, config, lib, ... }:
{
  imports = [
    ../vm/default.nix
  ];

  # Even more minimal for quick tests
  homebrew.casks = [
    "ghostty"
    "google-chrome"
  ];

  # Test-specific settings
  system.defaults.dock.tilesize = lib.mkForce 32;
}
```

### Option 3: Development VM

```nix
# hosts/dev-vm/default.nix
{ pkgs, config, lib, ... }:
{
  imports = [
    ../vm/default.nix
  ];

  # Add development tools
  homebrew.casks = [
    "visual-studio-code"
    "google-chrome"
    "ghostty"
    "rectangle"
    "docker"  # If testing Docker
  ];

  apps = {
    useBaseLists = true;
    systemPackagesToAdd = [
      "kubectl"
      "terraform"
    ];
  };
}
```

## VM-Specific Workflows

### Testing Configuration Changes

Before applying to your main machine:

```bash
# 1. Create VM with nix-me
# 2. Make configuration changes
# 3. Test in VM:
make switch

# 4. If it works, apply to main machine
# 5. Snapshot VM before changes for easy rollback
```

### Automated VM Testing

```bash
# Create fresh VM
nix-me vm create test-config

# Apply configuration
nix-me vm switch test-config

# Run tests
nix-me vm exec test-config "make check"

# Destroy when done
nix-me vm destroy test-config
```

## Customization Examples

### Ultra-Minimal VM (CLI only)

```nix
# Disable Homebrew GUI apps entirely
homebrew.casks = lib.mkForce [];

# Keep only essential CLI tools
environment.systemPackages = with pkgs; [
  git
  vim
  fish
];
```

### VM with Specific Test App

```nix
# Test a single app configuration
homebrew.casks = [
  "visual-studio-code"
  "your-app-to-test"
];
```

### CI/CD Runner VM

```nix
homebrew.casks = lib.mkForce [];  # No GUI needed

apps = {
  useBaseLists = false;
  systemPackagesToAdd = [
    "git"
    "nodejs_22"
    "python3"
    "docker"
  ];
};

# Enable SSH for remote access
services.nix-daemon.enable = true;
```

## Performance Tips

### Speed Up Builds

```bash
# Use binary cache
nix.settings = {
  substituters = [
    "https://cache.nixos.org/"
  ];
  trusted-public-keys = [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
  ];
};
```

### Reduce Disk Usage

```bash
# Regular garbage collection
nix-collect-garbage -d

# Optimize Nix store
nix-store --optimise
```

### VM Settings

For optimal performance:
- **CPU:** 2-4 cores minimum
- **RAM:** 4GB minimum, 8GB recommended
- **Disk:** 40GB minimum (Nix store can grow)
- **Graphics:** Minimal (VirtIO or VMSVGA)
- **Network:** Bridged or NAT

## Use Cases

Perfect for:
- **Testing configs** before deploying to production
- **Learning Nix** without risking your main system
- **CI/CD runners** for automated builds
- **Isolated development** environments
- **Quick experiments** with new packages
- **Training** and demonstrations
- **Regression testing** configuration changes

## Limitations in VMs

### What Doesn't Work

- **Mac App Store:** iCloud sign-in fails in most VMs
- **System Integrity Protection:** Some features limited
- **Hardware acceleration:** Graphics/video may be slower
- **TouchID/FaceID:** Not available
- **AirDrop/Handoff:** Continuity features don't work
- **Custom preferences:** Many system settings don't apply

### Workarounds

```nix
# Skip MAS apps
SKIP_MAS_APPS=1

# Use alternative packages
homebrew.casks = [
  "chromium"  # Instead of Safari
  "vlc"       # Instead of QuickTime
];
```

## VM Hypervisors

### UTM (Recommended for Apple Silicon)

- Free and open source
- Excellent Apple Silicon support
- QEMU backend
- Snapshots and save states

### VMware Fusion

- Professional features
- Good performance
- Commercial license required

### Parallels Desktop

- Best macOS guest support
- Fastest performance
- Commercial license required

### VirtualBox

- Free and open source
- Limited macOS support
- Intel only

## Snapshot Strategy

Before major changes:

1. **Take snapshot** "Before nix-me install"
2. **Install nix-me**
3. **Take snapshot** "After nix-me install"
4. **Make changes**
5. **Take snapshot** "After customization"

Revert to any point if needed.

## Related Configurations

- **shared:** Base configuration (VM uses minimal subset)
- **macbook:** Full laptop configuration
- **macbook-pro:** High-performance laptop configuration
- **macmini:** Desktop configuration
- **nixos-vm:** NixOS (Linux) VM configuration

## Converting VM Config to Physical Machine

Once tested, apply to real machine:

```bash
# 1. Export your host-specific config from VM
cd ~/.config/nixpkgs
git diff hosts/test-vm/default.nix

# 2. Create config for physical machine
cp hosts/test-vm/default.nix hosts/my-macbook/default.nix

# 3. Change machine type
# Edit to inherit from ../macbook instead of ../vm

# 4. Apply to physical machine
make switch HOSTNAME=my-macbook
```

## Troubleshooting

### VM-Specific Issues

**Spotlight indexing errors:**
```bash
# Already disabled in activation script
sudo mdutil -a -i off
```

**Homebrew install failures:**
```bash
# Use SKIP_BREW_ON_VM=1 for testing
# Or install Homebrew manually first
```

**Slow performance:**
- Increase CPU cores (4+ recommended)
- Increase RAM (8GB+ recommended)
- Use SSD for VM disk
- Disable Spotlight (done automatically)

**Screen resolution:**
```bash
# macOS VMs may need manual resolution setting
# Configure in VM settings, not nix-me
```

## Quick Start

```bash
# 1. Create macOS VM (UTM/VMware/Parallels)
# 2. Boot and set up macOS
# 3. Install nix-me:
curl -L https://raw.githubusercontent.com/lucamaraschi/nix-me/main/install.sh | \
  SKIP_MAS_APPS=1 bash

# 4. Choose "vm" as machine type
# 5. Build completes in ~10-15 minutes
# 6. Ready to test!
```

## Benefits of VM Testing

- ✅ **Safe:** Won't break your main machine
- ✅ **Fast:** Can snapshot and rollback instantly
- ✅ **Disposable:** Delete and recreate as needed
- ✅ **Isolated:** Test without affecting production
- ✅ **Reproducible:** Same config works on physical machines
- ✅ **Educational:** Learn Nix risk-free
