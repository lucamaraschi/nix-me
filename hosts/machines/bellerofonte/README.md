# Bellerofonte - MacBook Pro Configuration

**Machine Type:** MacBook Pro
**Owner:** batman
**Inherits From:** `macbook-pro` → `macbook` → `shared`

## Overview

Bellerofonte is a personal MacBook Pro configuration optimized for professional development work with enhanced performance settings and Pro-specific features.

## Inheritance Chain

```
hosts/shared/default.nix          (Layer 1: Base for all machines)
  ↓
hosts/macbook/default.nix         (Layer 2: MacBook optimizations)
  ↓
hosts/macbook-pro/default.nix     (Layer 3: MacBook Pro enhancements)
  ↓
hosts/bellerofonte/default.nix    (Layer 4: Machine-specific customizations)
```

## Key Features

### From MacBook Pro Base
- **Dock Size:** 36px (larger than regular MacBook's 32px)
- **High Performance Mode:** Enabled for M1 Pro/Max/Ultra
- **Battery Display:** Shows percentage in menu bar
- **Power Management:**
  - Display sleep: 20 min on battery, never on power
  - Power nap enabled on both battery and power
  - Disk sleep: 15 min on battery, never on power
- **Development Tools:** Kubernetes Helm CLI included

### From MacBook Base
- **Trackpad:** Optimized tap-to-click and natural scrolling
- **Battery Preservation:** Balanced performance/battery settings
- **Portability:** Settings optimized for on-the-go work

### From Shared Base
- **Complete Development Environment:** All CLI tools, GUI apps, fonts
- **Fish Shell:** Custom functions, shortcuts, autopair
- **1Password Integration:** SSH agent integration
- **Git Configuration:** Aliases, LFS, global ignores
- **macOS Preferences:** Dock, Finder, keyboard optimizations

## Installed Packages

### Development Tools (via Nix)
- Node.js 22, pnpm, npm, TypeScript
- Python 3
- Rust (via rustup)
- Go
- GitHub CLI (gh)
- Kubernetes Helm
- Network tools (nmap, dnsutils, mtr)
- File utilities (ripgrep, fd, eza, bat, tree)
- System monitoring (htop, ncdu)

### GUI Applications (via Homebrew)
- **Development:** Claude Code, VS Code, Docker Desktop, Ghostty, OrbStack, Orka Desktop
- **Communication:** Slack, Microsoft Teams, Zoom, Linear, Loom, Miro
- **Productivity:** 1Password, Raycast, Rectangle, Hammerspoon, Proton Mail/VPN
- **Design:** Figma, Adobe Creative Cloud
- **Virtualization:** UTM, VirtualBuddy, VMware Fusion
- **Media:** Spotify, OBS
- **Browsers:** Google Chrome
- **Office:** Microsoft Office

### CLI Tools (via Homebrew)
- coreutils, direnv, fd, gcc, git, grep
- jq, k3d, mas, ripgrep
- terraform, trash, helm

### Mac App Store
- Tailscale
- Xcode
- iA Writer

## Customization

To add machine-specific packages or settings, edit `hosts/bellerofonte/default.nix`:

```nix
apps = {
  useBaseLists = true;

  # Add GUI apps
  casksToAdd = [
    "your-app-here"
  ];

  # Add CLI tools
  brewsToAdd = [
    "your-tool-here"
  ];

  # Add Nix packages
  systemPackagesToAdd = [
    "your-package-here"
  ];

  # Remove unwanted packages
  casksToRemove = ["obs" "spotify"];
  brewsToRemove = ["terraform"];
  systemPackagesToRemove = ["go"];
};
```

## System Settings

### Dock
- Icon size: 36px
- Auto-hide: Configured in shared
- Position: Configured in shared

### Energy
- Display sleep: 20 min (battery), never (power)
- Power nap: Enabled
- Disk sleep: 15 min (battery), never (power)

### Performance
- High performance mode enabled (M1 Pro/Max/Ultra)
- Battery percentage visible
- Optimized for sustained workloads

## Building This Configuration

From the repository root:

```bash
# Build and switch
make switch HOSTNAME=bellerofonte

# Or if hostname is already set
make switch

# Check configuration
make check

# Update packages
make update switch
```

## Use Cases

Perfect for:
- Professional software development
- Resource-intensive tasks (compilation, virtualization)
- Multi-tasking with many applications
- Full-stack development with Docker/Kubernetes
- Design and creative work
- Video conferencing and collaboration
- Long coding sessions with external power

## Related Configurations

- **nabucodonosor:** Another MacBook (standard, not Pro)
- **macbook-pro (base):** Generic MacBook Pro template
- **macbook (base):** Generic MacBook template
- **shared:** Base configuration for all machines
