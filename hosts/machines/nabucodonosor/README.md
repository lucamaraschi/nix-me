# Nabucodonosor - MacBook Configuration

**Machine Type:** MacBook
**Owner:** batman
**Inherits From:** `macbook` → `shared`

## Overview

Nabucodonosor is a MacBook configuration optimized for portability, battery life, and mobile development work. It inherits from the standard MacBook base which focuses on battery preservation and trackpad optimization.

## Inheritance Chain

```
hosts/shared/default.nix          (Layer 1: Base for all machines)
  ↓
hosts/macbook/default.nix         (Layer 2: MacBook optimizations)
  ↓
hosts/nabucodonosor/default.nix   (Layer 3: Machine-specific customizations)
```

## Key Features

### From MacBook Base
- **Dock Size:** 32px (compact for smaller displays)
- **Battery Optimization:** Aggressive power management for extended battery life
  - Display sleep: 15 min on battery, 30 min on power
  - Computer sleep: 20 min on battery, never on power
  - Disk sleep: 10 min on battery, never on power
- **Trackpad:** Optimized tap-to-click and natural scrolling
- **Power Nap:** Only enabled when on power adapter
- **Wake for Network:** Only when plugged in

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
- nil (Nix language server)
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

To add machine-specific packages or settings, edit `hosts/nabucodonosor/default.nix`:

### Example: Remove Heavy Apps for Better Battery Life

```nix
apps = {
  useBaseLists = true;

  # Remove resource-intensive apps
  casksToRemove = [
    "vmware-fusion"
    "adobe-creative-cloud"
    "docker-desktop"  # Heavy on battery
    "obs"             # Not needed on mobile
  ];

  # Add lightweight alternatives
  casksToAdd = [
    "orbstack"        # Lighter Docker alternative
  ];
};
```

### Example: Mobile Developer Setup

```nix
apps = {
  useBaseLists = true;

  casksToAdd = [
    "sf-symbols"      # Apple design resources
    "proxyman"        # HTTP debugging
  ];

  brewsToAdd = [
    "ios-deploy"
    "cocoapods"
  ];

  systemPackagesToAdd = [
    "watchman"        # File watching for React Native
  ];
};
```

### Example: Extend Battery Life Further

```nix
# Even more aggressive battery saving
system.activationScripts.macbookOptimization.text = lib.mkForce ''
  echo "Ultra battery saving mode..." >&2

  # Shorter timeouts
  pmset -b displaysleep 10
  pmset -b sleep 15
  pmset -b disksleep 5

  # Disable everything on battery
  pmset -b powernap 0
  pmset -b womp 0
  pmset -b tcpkeepalive 0

  # Standard settings on power
  pmset -c displaysleep 30
  pmset -c sleep 0
  pmset -c disksleep 0
  pmset -c powernap 1
  pmset -c womp 1
'';
```

### Example: Custom Dock Size

```nix
# Slightly larger dock icons
system.defaults.dock.tilesize = lib.mkForce 36;
```

## System Settings

### Dock
- Icon size: 32px
- Auto-hide: Enabled
- Show recent apps: Disabled
- Position: Configured in shared

### Energy Management
- **Display sleep:** 15 min (battery), 30 min (power)
- **Computer sleep:** 20 min (battery), never (power)
- **Disk sleep:** 10 min (battery), never (power)
- **Power nap:** Power only
- **Wake for network:** Power only

### Trackpad
- Tap to click: Enabled
- Two-finger right click: Enabled
- Natural scrolling: Enabled

## Building This Configuration

From the repository root:

```bash
# Build and switch (if on this machine)
make switch

# Or specify hostname
make switch HOSTNAME=nabucodonosor

# Check configuration
make check

# Update packages
make update switch
```

## Use Cases

Perfect for:
- **Mobile development** - Working on the go, coffee shops, travel
- **Battery-conscious work** - Full day usage without charging
- **Lightweight development** - Web development, scripting, documentation
- **Meeting machine** - Video calls, presentations, collaboration
- **Secondary machine** - Complement to a desktop workstation
- **Learning and experimentation** - Safe environment for trying new tools

## Performance Characteristics

### Optimized For
- **Battery life:** 8-10 hour work sessions
- **Portability:** Frequent location changes
- **Trackpad use:** No external mouse
- **Smaller displays:** 13" MacBook screens
- **Mobile workflows:** Cloud services, remote access

### Resource Expectations
- **RAM:** 8GB minimum, 16GB recommended
- **Storage:** 256GB minimum for all packages
- **Battery:** Settings optimized for maximum runtime
- **Network:** Wi-Fi optimized (no Ethernet)

## Comparison: Nabucodonosor vs Bellerofonte

| Feature | Nabucodonosor (MacBook) | Bellerofonte (MacBook Pro) |
|---------|------------------------|----------------------------|
| **Type** | MacBook | MacBook Pro |
| **Focus** | Battery life | Performance |
| **Dock** | 32px | 36px |
| **Sleep (battery)** | 20 min | 20 min |
| **Display sleep (battery)** | 15 min | 20 min |
| **Disk sleep (battery)** | 10 min | 15 min |
| **Power nap** | Power only | Always |
| **Performance mode** | Standard | High |
| **Battery %** | Standard | Always shown |
| **Extra tools** | None | Kubernetes Helm |
| **Best for** | Mobile work | Desktop replacement |

## When to Use Bellerofonte Instead

Switch to Bellerofonte (MacBook Pro) when you need:
- More performance for intensive tasks
- Longer sustained workloads (compilation, rendering)
- Pro-specific development tools (Kubernetes, etc.)
- Larger display optimization (14" or 16")
- Desktop replacement laptop

## Tips for Mobile Use

1. **Monitor battery:** Check battery health with coconutbattery (optional cask)
2. **Use power adapter:** For long compilation or Docker work
3. **Close heavy apps:** When running on battery
4. **Leverage cloud:** Push heavy tasks to cloud/desktop machines
5. **Sync frequently:** Use git, iCloud, or Tailscale for file sync
6. **Hotspot ready:** Test mobile hotspot for reliable connectivity

## Connectivity

### Wi-Fi Optimization
```nix
# Optional: Add Wi-Fi location profiles
# system.defaults.CustomUserPreferences = {
#   "com.apple.wifi" = {
#     # Wi-Fi settings
#   };
# };
```

### Tailscale Integration
Already installed via Mac App Store (MAS). Use for:
- Secure remote access to home machines
- Access internal services on the go
- VPN alternative with better battery life

### 1Password SSH
SSH keys managed via 1Password agent. Works seamlessly:
```bash
ssh-add -l              # List keys
ssh -T git@github.com   # Test GitHub
```

## Related Configurations

- **bellerofonte:** MacBook Pro configuration (more performance)
- **macbook (base):** Generic MacBook template
- **shared:** Universal base for all machines
- **gotham:** Another MacBook instance (if exists)
- **work-macbook:** Example with work profile

## Switching Between Machines

If you work across nabucodonosor and bellerofonte:

```bash
# On nabucodonosor
git pull
make switch HOSTNAME=nabucodonosor

# On bellerofonte
git pull
make switch HOSTNAME=bellerofonte
```

All configs sync via git, ensuring consistency across machines.

## Cloud Development

Optimize for cloud/remote development:

```nix
apps = {
  useBaseLists = true;

  casksToAdd = [
    "visual-studio-code"   # With remote extensions
  ];

  brewsToAdd = [
    "mosh"                 # Better than SSH for mobile
  ];

  systemPackagesToAdd = [
    "tmux"                 # Already in base
  ];
};
```

Use VS Code Remote SSH to develop on more powerful machines while staying mobile.

## Backup Strategy

For a mobile machine:

1. **Time Machine:** To external drive or NAS
2. **Git:** Push all code frequently
3. **iCloud:** Documents and Desktop sync
4. **Dotfiles:** Managed by nix-me (this repo)

Your entire development environment can be recreated from:
```bash
git clone your-fork.git ~/.config/nixpkgs
cd ~/.config/nixpkgs
./install.sh
```
