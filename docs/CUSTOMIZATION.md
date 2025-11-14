# Customization Guide

This guide explains how to create custom configurations with profiles and specialized machine types.

## Architecture Overview

The configuration system uses a layered approach:

```
┌─────────────────────────────────────────┐
│  Individual Host Config                  │
│  hosts/<hostname>/default.nix            │
│  (Machine-specific overrides)            │
└─────────────────────────────────────────┘
                  ↓ overrides
┌─────────────────────────────────────────┐
│  Profile Modules (Optional)              │
│  hosts/profiles/{work,personal}.nix      │
│  (Environment-specific settings)         │
└─────────────────────────────────────────┘
                  ↓ overrides
┌─────────────────────────────────────────┐
│  Machine Type                            │
│  hosts/{macbook,macbook-pro,macmini,vm}  │
│  (Hardware-specific optimizations)       │
└─────────────────────────────────────────┘
                  ↓ inherits
┌─────────────────────────────────────────┐
│  Shared Base Configuration               │
│  hosts/shared/default.nix                │
│  (Common to all machines)                │
└─────────────────────────────────────────┘
```

## Creating Custom Profiles

### 1. Profile-Based Approach (Recommended)

Profiles are reusable modules that can be mixed into any machine type.

**Example: Work Profile** (`hosts/profiles/work.nix`)

```nix
{ config, pkgs, lib, ... }:
{
  apps = {
    useBaseLists = true;

    casksToAdd = [
      "microsoft-teams"
      "slack"
      "docker-desktop"
    ];

    casksToRemove = [
      "spotify"
      "obs"
    ];
  };

  system.defaults = {
    screensaver = {
      askForPassword = true;
      askForPasswordDelay = 5; # Lock quickly for security
    };
  };
}
```

**Example: Personal Profile** (`hosts/profiles/personal.nix`)

```nix
{ config, pkgs, lib, ... }:
{
  apps = {
    useBaseLists = true;

    casksToAdd = [
      "spotify"
      "obs"
      "steam"
    ];

    casksToRemove = [
      "microsoft-teams"
      "linear-linear"
    ];
  };

  system.defaults = {
    screensaver.askForPasswordDelay = 300; # More relaxed
  };
}
```

### 2. Using Profiles in flake.nix

```nix
darwinConfigurations = {
  "work-macbook-pro" = mkDarwinSystem {
    hostname = "work-macbook-pro";
    machineType = "macbook-pro";
    machineName = "Work MacBook Pro";
    username = "yourusername";
    extraModules = [
      ./hosts/profiles/work.nix
    ];
  };

  "personal-macbook-pro" = mkDarwinSystem {
    hostname = "personal-macbook-pro";
    machineType = "macbook-pro";
    machineName = "Personal MacBook Pro";
    username = "yourusername";
    extraModules = [
      ./hosts/profiles/personal.nix
    ];
  };
};
```

## Creating Custom Machine Types

### Example: MacBook Pro Type

Create `hosts/macbook-pro/default.nix`:

```nix
{ pkgs, config, lib, ... }:
{
  # Import base macbook configuration
  imports = [
    ../macbook/default.nix
  ];

  # MacBook Pro-specific overrides
  system.defaults = {
    dock = {
      tilesize = lib.mkForce 36; # Larger display
    };
  };

  # Pro-specific power management
  system.activationScripts.macbookProOptimization.text = ''
    pmset -b displaysleep 20
    pmset -c displaysleep 0
  '';
}
```

## Available Machine Types

### Built-in Types

1. **macbook** - General MacBook (Air/Pro)
   - Battery optimization
   - Trackpad settings
   - Smaller UI elements

2. **macbook-pro** - MacBook Pro optimizations
   - Inherits from macbook
   - Performance-focused
   - Less aggressive power saving

3. **macmini** - Mac Mini desktop
   - Multi-display support
   - Performance optimization
   - Larger UI elements

4. **vm** - Virtual Machine
   - Minimal packages
   - Reduced resource usage
   - Fast boot

## App Inheritance System

The system uses a powerful add/remove pattern:

```nix
apps = {
  # Start with base list
  useBaseLists = true;

  # Add apps
  casksToAdd = [
    "spotify"
    "docker"
  ];

  # Remove apps from base
  casksToRemove = [
    "adobe-creative-cloud"
    "vmware-fusion"
  ];

  # CLI tools
  systemPackagesToAdd = [
    "ripgrep"
    "jq"
  ];

  systemPackagesToRemove = [
    "nodejs"  # If you want different Node setup
  ];
};
```

## Real-World Examples

### Example 1: Work MacBook Pro (Software Engineer)

```nix
"dev-macbook" = mkDarwinSystem {
  hostname = "dev-macbook";
  machineType = "macbook-pro";
  machineName = "Dev MacBook";
  username = "developer";
  extraModules = [
    ./hosts/profiles/work.nix
    {
      # Additional work-specific customizations
      apps = {
        casksToAdd = [
          "visual-studio-code"
          "docker-desktop"
          "postman"
          "tableplus"
        ];
        systemPackagesToAdd = [
          "kubectl"
          "terraform"
          "awscli2"
        ];
      };
    }
  ];
};
```

### Example 2: Personal MacBook (Creative Work)

```nix
"creative-macbook" = mkDarwinSystem {
  hostname = "creative-macbook";
  machineType = "macbook-pro";
  machineName = "Creative MacBook";
  username = "artist";
  extraModules = [
    ./hosts/profiles/personal.nix
    {
      apps = {
        casksToAdd = [
          "adobe-creative-cloud"
          "figma"
          "blender"
          "obs"
        ];
        systemPackagesToAdd = [
          "ffmpeg"
          "imagemagick"
          "gifsicle"
        ];
      };
    }
  ];
};
```

### Example 3: Home Studio (Mac Mini)

```nix
"home-studio" = mkDarwinSystem {
  hostname = "home-studio";
  machineType = "macmini";
  machineName = "Home Studio";
  username = "producer";
  extraModules = [
    ./hosts/profiles/personal.nix
    {
      apps = {
        casksToAdd = [
          "logic-pro"
          "ableton-live"
          "spotify"
        ];
      };

      system.defaults = {
        dock.tilesize = lib.mkForce 64; # Large dock for studio
      };
    }
  ];
};
```

### Example 4: Combined Work + Personal

```nix
"hybrid-macbook" = mkDarwinSystem {
  hostname = "hybrid-macbook";
  machineType = "macbook-pro";
  machineName = "Hybrid MacBook";
  username = "freelancer";
  extraModules = [
    # Import both profiles - later overrides earlier
    ./hosts/profiles/work.nix
    ./hosts/profiles/personal.nix
    {
      # Fine-tune the combination
      apps = {
        casksToAdd = [
          # Keep both work and personal apps
          "microsoft-teams"  # Work
          "spotify"          # Personal
        ];
      };
    }
  ];
};
```

## Per-Machine Overrides

Create `hosts/<hostname>/default.nix` for machine-specific settings:

```nix
{ config, pkgs, lib, ... }:
{
  # This machine has specific needs
  apps = {
    useBaseLists = true;
    casksToAdd = [
      "amphetamine"  # Only this machine needs this
    ];
  };

  # Machine-specific system preferences
  system.defaults = {
    dock.tilesize = 48;  # I prefer this on this specific Mac
  };
}
```

## Creating Your Configuration

### Option 1: Using the Wizard

```bash
nix-me setup

# Follow prompts:
# 1. Choose machine type (or create new)
# 2. Select profile (work/personal)
# 3. Customize apps
```

### Option 2: Manual Creation

1. **Create your profile** (optional):
   ```bash
   # Create a new profile
   cp hosts/profiles/work.nix hosts/profiles/myprofile.nix
   # Edit as needed
   ```

2. **Add to flake.nix**:
   ```nix
   "my-machine" = mkDarwinSystem {
     hostname = "my-machine";
     machineType = "macbook-pro";
     machineName = "My Machine";
     username = "myuser";
     extraModules = [
       ./hosts/profiles/myprofile.nix
     ];
   };
   ```

3. **Build and apply**:
   ```bash
   make switch HOST=my-machine
   ```

## Tips and Best Practices

1. **Start with a profile** - Use work or personal as a template
2. **Test incrementally** - Add apps gradually, test with `make build`
3. **Use inheritance** - Build on existing machine types
4. **Keep profiles focused** - One profile per environment type
5. **Document changes** - Comment your customizations
6. **Backup before major changes** - `git commit` frequently

## Troubleshooting

**Problem**: Apps from base list keep appearing
```nix
# Solution: Use casksToRemove
apps = {
  useBaseLists = true;
  casksToRemove = ["unwanted-app"];
};
```

**Problem**: Want completely different app list
```nix
# Solution: Disable base lists
apps = {
  useBaseLists = false;
  # Now define everything manually
};
```

**Problem**: Profile conflicts
```nix
# Solution: Order matters - later modules override earlier ones
extraModules = [
  ./hosts/profiles/work.nix      # Applied first
  ./hosts/profiles/personal.nix  # Overrides work
  { /* your overrides */ }       # Overrides both
];
```

## Next Steps

- Create your first profile: `cp hosts/profiles/work.nix hosts/profiles/myprofile.nix`
- Add it to flake.nix
- Run `make build` to test
- Run `make switch` to activate

For more help: `nix-me --help` or check the main README.md
