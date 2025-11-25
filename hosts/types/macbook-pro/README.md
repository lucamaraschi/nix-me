# MacBook Pro - Base Configuration

**Type:** Base Template
**Inherits From:** `macbook` → `shared`
**Used By:** `bellerofonte`, `work-macbook-pro`, `personal-macbook-pro`

## Overview

This is the base configuration template for all MacBook Pro machines. It provides Pro-specific optimizations and settings that enhance the standard MacBook configuration with better performance, larger UI elements, and professional development tools.

## Purpose

Use this configuration for:
- MacBook Pro 13", 14", or 16" models
- M1 Pro, M1 Max, M1 Ultra, M2 Pro, M2 Max, M3 Pro, M3 Max
- Machines with higher performance requirements
- Professional development workstations
- Desktop replacement laptops

## Inheritance Chain

```
hosts/shared/default.nix     (Layer 1: Base for all machines)
  ↓
hosts/macbook/default.nix    (Layer 2: MacBook optimizations)
  ↓
hosts/macbook-pro/default.nix (Layer 3: MacBook Pro enhancements)
```

## Key Differences from Regular MacBook

### Display & UI
- **Dock Icons:** 36px (vs 32px on regular MacBook)
- **Rationale:** MacBook Pro typically has larger/higher resolution displays

### Performance
- **High Performance Mode:** Enabled for M1 Pro/Max/Ultra chips
- **Custom Preferences:** SystemProfiler performance mode set to "high"

### Power Management
- **Less Aggressive:** Longer timeouts than MacBook Air
- **Display Sleep:**
  - Battery: 20 minutes (vs 15 on regular MacBook)
  - Power: Never sleep
- **Disk Sleep:**
  - Battery: 15 minutes
  - Power: Never sleep
- **Power Nap:** Enabled on both battery and power

### Battery Display
- **Menu Bar:** Shows battery percentage
- **Rationale:** Pro users typically want detailed battery info

### Development Tools
- **Kubernetes Helm:** Pre-installed via Nix
- **Rationale:** Pro machines have resources for container orchestration

## Technical Details

### Activation Scripts

The configuration includes a custom activation script `macbookProOptimization.text` that:
- Sets energy preferences via `pmset`
- Configures display sleep timings
- Enables power nap
- Configures disk sleep settings

### System Defaults

```nix
system.defaults = {
  dock = {
    tilesize = lib.mkForce 36;
  };

  CustomUserPreferences = {
    "com.apple.controlcenter".BatteryShowPercentage = true;
    "com.apple.SystemProfiler".PerformanceMode = "high";
  };
};
```

### Package Additions

```nix
apps = {
  systemPackagesToAdd = [
    "kubernetes-helm"  # Helm CLI via Nix
  ];
};
```

Note: docker-desktop is already available via base installations.nix as a Homebrew cask.

## Creating a New MacBook Pro Machine

### Option 1: Use as-is in flake.nix

```nix
"my-macbook-pro" = mkDarwinSystem {
  hostname = "my-macbook-pro";
  machineType = "macbook-pro";
  machineName = "My MacBook Pro";
  username = "yourusername";
};
```

### Option 2: Create host-specific config

1. Create `hosts/my-macbook-pro/default.nix`:

```nix
{ pkgs, config, lib, ... }:
{
  imports = [
    ../macbook-pro/default.nix
  ];

  # Add your customizations here
  apps = {
    useBaseLists = true;
    casksToAdd = [ "postman" ];
    systemPackagesToAdd = [ "kubectl" ];
  };
}
```

2. Add to flake.nix:

```nix
"my-macbook-pro" = mkDarwinSystem {
  hostname = "my-macbook-pro";
  machineType = "macbook-pro";
  machineName = "My MacBook Pro";
  username = "yourusername";
};
```

## Customization Examples

### Override dock size

```nix
system.defaults.dock.tilesize = lib.mkForce 40;  # Even larger
```

### Disable high performance mode

```nix
system.defaults.CustomUserPreferences = {
  "com.apple.SystemProfiler".PerformanceMode = lib.mkForce "normal";
};
```

### Add Pro-specific tools

```nix
apps = {
  useBaseLists = true;
  brewsToAdd = [
    "kubernetes-cli"
    "terraform"
    "ansible"
  ];
  casksToAdd = [
    "docker"
    "postman"
    "parallels"
  ];
};
```

## Performance Characteristics

### Resource Expectations
- **RAM:** 16GB minimum, 32GB+ recommended
- **Storage:** Fast SSD with plenty of space for Docker images
- **CPU:** M1 Pro or better for optimal performance settings

### Power Profile
- Optimized for **sustained workloads**
- Less battery conservation than regular MacBook
- Assumes frequent access to power adapter
- Power nap keeps system updated even when sleeping

## When NOT to Use This

Use the regular `macbook` configuration instead if:
- You have a MacBook Air
- You have a base MacBook Pro (M1, M2, M3 without Pro/Max)
- Battery life is your primary concern
- You don't need the extra performance tools
- You prefer more conservative power management

## Related Configurations

- **macbook:** Base configuration for regular MacBooks
- **macmini:** Desktop Mac configuration
- **shared:** Universal base for all machines
- **bellerofonte:** Example MacBook Pro instance
- **work-macbook-pro:** Example with work profile
- **personal-macbook-pro:** Example with personal profile
