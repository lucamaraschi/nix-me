# MacBook - Base Configuration

**Type:** Base Template
**Inherits From:** `shared`
**Used By:** `nabucodonosor`, `gotham`, `macbook-air`, `macbook-pro` (as parent)

## Overview

This is the base configuration template for all MacBook machines (including MacBook Air and as a parent for MacBook Pro). It provides laptop-specific optimizations focused on portability, battery life, and trackpad usage.

## Purpose

Use this configuration for:
- MacBook Air (all models)
- MacBook (base models)
- MacBook Pro 13" (M1, M2, M3 base models)
- Any Mac laptop where battery life is important
- Parent configuration for MacBook Pro

## Inheritance Chain

```
hosts/shared/default.nix   (Layer 1: Base for all machines)
  ↓
hosts/macbook/default.nix  (Layer 2: MacBook optimizations)
```

## Key Features

### Battery Optimization
Aggressive power management to maximize battery life:

- **Display Sleep:**
  - Battery: 15 minutes
  - Power adapter: 30 minutes
- **Computer Sleep:**
  - Battery: 20 minutes
  - Power adapter: Never
- **Disk Sleep:**
  - Battery: 10 minutes
  - Power adapter: Never
- **Power Nap:** Enabled on power adapter only

### Display & UI
- **Dock Icons:** 32px (smaller for laptop screens)
- **Rationale:** Maximize screen real estate on smaller displays

### Trackpad Optimization
Enhanced trackpad settings for laptop use:

```nix
trackpad = {
  Clicking = true;                    # Tap to click
  TrackpadRightClick = true;          # Two-finger right click
  TrackpadThreeFingerDrag = false;    # Disabled (use gestures instead)
};

NSGlobalDomain = {
  "com.apple.swipescrolldirection" = true;  # Natural scrolling
};
```

### Sleep Settings
- **Wake for Network Access:** Enabled on power, disabled on battery
- **Rationale:** Stay connected when plugged in, save battery when mobile

## Technical Details

### Activation Script

The `macbookOptimization.text` script runs on each system activation:

```bash
# Battery preservation mode
pmset -b displaysleep 15     # 15 min on battery
pmset -c displaysleep 30     # 30 min on power

pmset -b sleep 20            # Sleep after 20 min on battery
pmset -c sleep 0             # Never sleep on power

pmset -b disksleep 10        # Disk sleep 10 min on battery
pmset -c disksleep 0         # Never on power

# Power nap only on AC power
pmset -b powernap 0
pmset -c powernap 1

# Wake for network only when on power
pmset -b womp 0
pmset -c womp 1
```

### System Defaults

```nix
system.defaults = {
  dock = {
    tilesize = lib.mkForce 32;  # Compact dock for smaller screens
  };

  trackpad = {
    Clicking = true;
    TrackpadRightClick = true;
    TrackpadThreeFingerDrag = false;
  };

  NSGlobalDomain = {
    "com.apple.swipescrolldirection" = true;
  };
};
```

## Creating a New MacBook Machine

### Option 1: Simple (just use machineType)

```nix
# In flake.nix
"my-macbook" = mkDarwinSystem {
  hostname = "my-macbook";
  machineType = "macbook";
  machineName = "My MacBook";
  username = "yourusername";
};
```

### Option 2: With host-specific config

1. Create `hosts/my-macbook/default.nix`:

```nix
{ pkgs, config, lib, ... }:
{
  imports = [
    ../macbook/default.nix
  ];

  # Your customizations
  apps = {
    useBaseLists = true;

    # Remove heavy apps you don't need on laptop
    casksToRemove = [
      "vmware-fusion"
      "adobe-creative-cloud"
    ];

    # Add laptop-specific tools
    casksToAdd = [
      "amphetamine"      # Keep awake when needed
      "coconutbattery"   # Battery health monitoring
    ];
  };

  # Override dock size if desired
  system.defaults.dock.tilesize = lib.mkForce 36;
}
```

2. Add to flake.nix with the same `mkDarwinSystem` call.

## Customization Examples

### More Aggressive Battery Saving

```nix
system.activationScripts.macbookOptimization.text = lib.mkForce ''
  echo "Ultra battery saving mode..." >&2
  pmset -b displaysleep 10   # Even shorter timeouts
  pmset -b sleep 15
  pmset -b disksleep 5

  # Disable everything on battery
  pmset -b powernap 0
  pmset -b womp 0
  pmset -b tcpkeepalive 0
'';
```

### Desktop Replacement Mode

```nix
system.activationScripts.macbookOptimization.text = lib.mkForce ''
  echo "Desktop replacement mode..." >&2

  # Never sleep on battery (clamshell with external display)
  pmset -b displaysleep 0
  pmset -b sleep 0
  pmset -b disksleep 0

  # Same for power
  pmset -c displaysleep 0
  pmset -c sleep 0
  pmset -c disksleep 0
'';
```

### Disable Tap to Click

```nix
system.defaults.trackpad.Clicking = lib.mkForce false;
```

## Packages

MacBook configurations inherit all packages from the `shared` base:
- Complete development environment (Node.js, Python, Rust, Go)
- All GUI applications via Homebrew
- All CLI tools
- Fonts and system utilities

See `hosts/shared/README.md` for the complete list.

## Performance Characteristics

### Optimized For
- **Portability:** Frequent location changes
- **Battery life:** Extended use away from power
- **Trackpad usage:** No external mouse
- **Smaller displays:** 13" screens

### Resource Expectations
- **RAM:** 8GB minimum, 16GB recommended
- **Storage:** 256GB minimum for all packages
- **Battery:** Settings optimized for 8-10 hour usage

## When to Use MacBook Pro Instead

Use `macbook-pro` configuration if:
- You have M1/M2/M3 Pro, Max, or Ultra chips
- Performance is more important than battery life
- You frequently use the laptop plugged in
- You need Pro-specific development tools (Helm, etc.)
- You have a larger display (14" or 16")

## When to Use Mac Mini Instead

Use `macmini` configuration if:
- Desktop Mac (no battery)
- Always connected to power
- Multiple external displays
- Server/build machine use case

## Related Configurations

- **macbook-pro:** Enhanced MacBook with Pro optimizations
- **macmini:** Desktop Mac configuration
- **shared:** Universal base for all machines
- **nabucodonosor:** Example MacBook instance
- **gotham:** Example MacBook instance
- **work-macbook:** Example with work profile
