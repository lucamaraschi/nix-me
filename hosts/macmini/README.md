# Mac Mini - Desktop Configuration

**Type:** Base Template
**Inherits From:** `shared`
**Used By:** `mac-mini`, `home-studio`

## Overview

This is the base configuration template for Mac Mini machines. It provides desktop-specific optimizations focused on performance, multi-display support, and always-on operation without battery concerns.

## Purpose

Use this configuration for:
- Mac Mini (all models: M1, M2, M3, Intel)
- Desktop Mac always connected to power
- Home servers and build machines
- Media centers and home studios
- Multi-display workstations

## Inheritance Chain

```
hosts/shared/default.nix  (Layer 1: Base for all machines)
  ↓
hosts/macmini/default.nix (Layer 2: Mac Mini optimizations)
```

## Key Features

### Display & UI Optimizations

**Dock Settings:**
- **Auto-hide:** Disabled (always visible on desktop)
- **Icon size:** 48px (larger for desktop displays)
- **Magnification:** Enabled with 64px large size
- **Orientation:** Bottom

**Desktop:**
- **Desktop icons:** Enabled (unlike laptops where space is limited)
- **Window persistence:** Keeps windows when quitting apps

### Power Management

Optimized for **24/7 desktop operation**:

```nix
system.activationScripts.macminiOptimization.text = ''
  # Never sleep the display on a desktop
  pmset displaysleep 0

  # Turn on power nap
  pmset powernap 1

  # Never sleep the disks
  pmset disksleep 0

  # Optimize for performance
  pmset standby 0
'';
```

**Settings explained:**
- **Display sleep:** Never (desktop is always in use)
- **Disk sleep:** Never (server/build use requires constant access)
- **Power nap:** Always enabled (keep system updated)
- **Standby:** Disabled (no need for battery-saving modes)

### Package Additions

Mac Mini configurations include desktop-friendly packages:

**Media & Entertainment:**
- Spotify (streaming music)
- OBS (recording/streaming)

**Professional Tools:**
- Adobe Creative Cloud
- Figma

**Development (Extended):**
- Docker
- OrbStack
- VMware Fusion

**Office & Productivity:**
- Microsoft Office
- Microsoft Teams

## Technical Details

### System Defaults

```nix
system.defaults = {
  dock = {
    autohide = lib.mkForce false;
    tilesize = lib.mkForce 48;
    magnification = lib.mkForce true;
    largesize = lib.mkForce 64;
    orientation = lib.mkForce "bottom";
  };

  finder = {
    CreateDesktop = lib.mkForce true;
  };
};
```

### Application Configuration

```nix
apps = {
  useBaseLists = true;
  casksToAdd = [
    "spotify"
    "obs"
    "adobe-creative-cloud"
    "figma"
    "docker"
    "orbstack"
    "vmware-fusion"
    "microsoft-office"
    "microsoft-teams"
  ];
};
```

## Creating a New Mac Mini Machine

### Option 1: Simple (use machineType in flake.nix)

```nix
"my-mac-mini" = mkDarwinSystem {
  hostname = "my-mac-mini";
  machineType = "macmini";
  machineName = "My Mac Mini";
  username = "yourusername";
};
```

### Option 2: With host-specific config

1. Create `hosts/my-mac-mini/default.nix`:

```nix
{ pkgs, config, lib, ... }:
{
  imports = [
    ../macmini/default.nix
  ];

  # Add server-specific customizations
  apps = {
    useBaseLists = true;

    # Add build tools
    brewsToAdd = [
      "jenkins"
      "postgresql"
    ];

    # Remove apps not needed on headless server
    casksToRemove = [
      "spotify"
      "obs"
      "adobe-creative-cloud"
    ];
  };

  # Enable SSH for remote access
  services.nix-daemon.enable = true;
}
```

2. Add to flake.nix with the same `mkDarwinSystem` call.

## Customization Examples

### Home Media Server

```nix
apps = {
  useBaseLists = true;

  casksToAdd = [
    "plex-media-server"
    "transmission"  # BitTorrent client
    "handbrake"     # Video transcoding
  ];

  casksToRemove = [
    "microsoft-office"
    "microsoft-teams"
    "adobe-creative-cloud"
  ];

  brewsToAdd = [
    "ffmpeg"
    "yt-dlp"
  ];
};
```

### Build/CI Server

```nix
apps = {
  useBaseLists = true;

  casksToAdd = [
    "docker"
  ];

  casksToRemove = [
    "spotify"
    "obs"
    "adobe-creative-cloud"
    "figma"
  ];

  brewsToAdd = [
    "jenkins"
    "postgresql"
    "redis"
  ];

  systemPackagesToAdd = [
    "cmake"
    "autoconf"
    "automake"
  ];
};
```

### Creative Workstation

```nix
system.defaults.dock = {
  tilesize = lib.mkForce 56;  # Even larger for 4K display
  largesize = lib.mkForce 72;
};

apps = {
  useBaseLists = true;

  casksToAdd = [
    "adobe-creative-cloud"
    "figma"
    "sketch"
    "blender"
    "affinity-designer"
    "affinity-photo"
  ];
};
```

### Dual Display Setup

```nix
system.defaults = {
  # Keep dock on main display
  dock = {
    autohide = lib.mkForce false;
    orientation = lib.mkForce "left";  # Or "right" depending on layout
  };

  # Optimize for multi-display
  NSGlobalDomain = {
    AppleShowAllExtensions = true;
    _HIHideMenuBar = false;  # Always show menu bar
  };
};
```

## Use Cases

Perfect for:
- **Home Studio:** Music production, video editing, content creation
- **Build Server:** CI/CD, compilation, automated testing
- **Media Server:** Plex, home theater PC, streaming
- **Development Workstation:** Multi-display coding setup
- **Home Office:** Desk-based work with external displays
- **Always-on Services:** File server, backup server, home automation hub

## Performance Characteristics

### Optimized For
- **24/7 operation:** No sleep modes
- **Multi-display setups:** 2-6 external monitors
- **High performance:** No battery-saving restrictions
- **Server workloads:** Build jobs, containerized services
- **Media processing:** Video transcoding, audio production

### Resource Expectations
- **RAM:** 16GB minimum, 32GB+ recommended for server/build use
- **Storage:** 512GB+ for media server, VM hosting
- **Network:** Gigabit Ethernet (built-in, not Wi-Fi)
- **Displays:** Support for multiple 4K/5K monitors

## When NOT to Use This

Use other configurations if:
- **Portability needed:** Use `macbook` or `macbook-pro`
- **Battery operation:** Use `macbook` configurations
- **Testing/VMs:** Use `vm` configuration
- **Minimal footprint:** Use `vm` configuration

## Differences from MacBook

| Feature | Mac Mini | MacBook |
|---------|----------|---------|
| Dock auto-hide | Disabled | Enabled |
| Dock icon size | 48px | 32px |
| Display sleep | Never | 15-20 min (battery) |
| Disk sleep | Never | 10-15 min (battery) |
| Power nap | Always | Power only |
| Desktop icons | Enabled | Often disabled |
| Magnification | Enabled | Disabled |
| Battery mgmt | None | Extensive |
| Typical RAM | 16-64GB | 8-32GB |

## System Requirements

- macOS 10.15+ (Catalina or later)
- Mac Mini (2018 or later recommended)
- External display(s)
- Wired Ethernet connection (recommended)
- Sufficient cooling (ensure adequate ventilation)

## Related Configurations

- **macbook:** Laptop configuration with battery optimization
- **macbook-pro:** High-performance laptop configuration
- **vm:** Virtual machine configuration
- **shared:** Universal base for all machines
- **home-studio:** Example Mac Mini with personal profile
- **mac-mini:** Generic Mac Mini instance

## Network Services

Mac Mini is ideal for hosting services. Consider:

```nix
# Enable SSH (already in nix-darwin)
services.nix-daemon.enable = true;

# Example: Run background services
# Add to your host-specific config:
launchd.daemons = {
  # Your service definitions
};
```

## Backup Considerations

For always-on Mac Mini:

```nix
# Time Machine to NAS
# Add backup configuration

# Or use scheduled backup scripts
# Via launchd or cron
```

## Remote Access

For headless operation:

```nix
# Enable screen sharing
system.defaults.CustomUserPreferences = {
  "com.apple.screensharing" = {
    # Screen sharing settings
  };
};

# SSH is already available via nix-darwin
# Access via: ssh username@mac-mini.local
```

## Tips

1. **External Displays:** Mac Mini supports multiple displays - configure dock position accordingly
2. **Cooling:** Ensure good ventilation, especially under sustained load
3. **Network:** Use Ethernet for server workloads, not Wi-Fi
4. **Storage:** Consider external SSD for media/build artifacts
5. **Monitoring:** Add htop, glances, or other monitoring tools
6. **Headless:** Can run without display attached for server use
