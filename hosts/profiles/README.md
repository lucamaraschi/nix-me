# Profiles - Work and Personal Configurations

**Type:** Optional Configuration Layers
**Inherits From:** N/A (applied as extra modules)
**Used By:** Any machine via `extraModules` parameter

## Overview

Profiles are reusable configuration modules that customize machines for specific contexts (work vs personal). They layer on top of the base machine configuration to add context-specific applications, tools, and settings.

## Architecture

Profiles use the `extraModules` parameter in `mkDarwinSystem`:

```nix
"work-macbook-pro" = mkDarwinSystem {
  hostname = "work-macbook-pro";
  machineType = "macbook-pro";
  machineName = "Work MacBook Pro";
  username = "batman";
  extraModules = [
    ./hosts/profiles/work.nix  # Apply work profile
  ];
};
```

## Layering Structure

```
Layer 1: hosts/shared/default.nix        (Base packages & settings)
  ↓
Layer 2: hosts/${machineType}/           (Machine-type optimizations)
  ↓
Layer 3: hosts/profiles/${profile}.nix   (Context: work or personal)
  ↓
Layer 4: hosts/${hostname}/              (Optional host-specific)
```

## Available Profiles

### Work Profile (`work.nix`)

Optimizes the machine for professional/corporate use.

**Philosophy:** Security-focused, productivity-oriented, enterprise tools

**Applications Added:**
- **Communication:** Microsoft Teams, Slack, Zoom
- **Productivity:** Microsoft Office, Linear
- **Development:** Docker Desktop, VS Code, Postman

**Applications Removed:**
- Spotify (personal entertainment)
- OBS (streaming/recording)

**CLI Tools Added:**
- terraform (infrastructure as code)
- kubectl (Kubernetes CLI)
- helm (Kubernetes package manager)
- awscli2 (AWS command line)

**Security Settings:**
- Screen lock: 5 seconds after screensaver starts
- Stricter security preferences
- Telemetry/analytics disabled

**System Preferences:**
- Automatic capitalization: Disabled
- Spell correction: Disabled

**Environment Variables:**
- `WORK_ENV=production`
- (Add company-specific variables)

### Personal Profile (`personal.nix`)

Optimizes the machine for personal use, creativity, and entertainment.

**Philosophy:** Creative-focused, entertainment-friendly, relaxed security

**Applications Added:**
- **Entertainment:** Spotify, OBS, Steam
- **Creative:** Adobe Creative Cloud, Figma
- **Productivity:** Notion, Todoist

**Applications Removed:**
- Microsoft Teams (work communication)
- Microsoft Office (work productivity)
- Linear (work project management)

**CLI Tools Added:**
- yt-dlp (YouTube downloader)
- ffmpeg (media processing)
- transmission-cli (torrent client)

**Security Settings:**
- Screen lock: 5 minutes after screensaver
- More relaxed preferences

**System Preferences:**
- Larger dock: 48px icons
- More visible UI elements

**Environment Variables:**
- `PERSONAL_PROJECTS=$HOME/Projects`

## Usage Examples

### Work MacBook Pro

```nix
# In flake.nix
"work-macbook-pro" = mkDarwinSystem {
  hostname = "work-macbook-pro";
  machineType = "macbook-pro";
  machineName = "Work MacBook Pro";
  username = "batman";
  extraModules = [
    ./hosts/profiles/work.nix
  ];
};
```

**Result:**
- MacBook Pro base configuration
- + Work-specific apps (Teams, Office, Docker)
- + Work CLI tools (kubectl, terraform, helm)
- + Stricter security
- - Personal apps removed (Spotify, OBS)

### Personal MacBook

```nix
"personal-macbook" = mkDarwinSystem {
  hostname = "personal-macbook";
  machineType = "macbook";
  machineName = "Personal MacBook";
  username = "batman";
  extraModules = [
    ./hosts/profiles/personal.nix
  ];
};
```

**Result:**
- MacBook base configuration
- + Entertainment apps (Spotify, Steam, OBS)
- + Creative tools (Adobe CC, Figma)
- + Media tools (ffmpeg, yt-dlp)
- + Larger UI for easier access
- - Work apps removed (Teams, Office)

### Mac Mini Home Studio

```nix
"home-studio" = mkDarwinSystem {
  hostname = "home-studio";
  machineType = "macmini";
  machineName = "Home Studio";
  username = "batman";
  extraModules = [
    ./hosts/profiles/personal.nix
  ];
};
```

**Result:**
- Mac Mini desktop configuration
- + Personal profile for creative work
- + Entertainment and media tools
- Desktop optimizations + creative focus

### Machine Without Profile

```nix
"generic-macbook" = mkDarwinSystem {
  hostname = "generic-macbook";
  machineType = "macbook";
  machineName = "Generic MacBook";
  username = "batman";
  # No extraModules = gets base + machine-type only
};
```

**Result:**
- All base packages from shared
- Machine-type optimizations
- No profile-specific additions/removals

## Comparing Profiles

| Feature | Work Profile | Personal Profile | No Profile |
|---------|-------------|------------------|------------|
| **Focus** | Enterprise | Creative/Entertainment | Neutral |
| **Security** | Strict (5s lock) | Relaxed (5m lock) | Default |
| **Office Apps** | Microsoft Office | Notion, Todoist | Base only |
| **Communication** | Teams, Slack, Zoom | N/A | Slack, Zoom |
| **Entertainment** | ❌ Removed | Spotify, Steam, OBS | Spotify, OBS |
| **Creative Tools** | ❌ Limited | Adobe CC, Figma | Figma, Adobe CC |
| **Dev Tools** | Docker, Postman | Standard | Standard |
| **Cloud Tools** | AWS, Terraform, K8s | ❌ None | N/A |
| **Media Tools** | ❌ None | ffmpeg, yt-dlp | N/A |
| **Dock Size** | Default | 48px (larger) | Default |

## Creating Custom Profiles

### Example: Freelance Profile

```nix
# hosts/profiles/freelance.nix
{ config, pkgs, lib, ... }:
{
  apps = {
    useBaseLists = true;

    casksToAdd = [
      # Client communication
      "slack"
      "zoom"
      "notion"

      # Invoicing & time tracking
      "toggl-track"
      "harvest"

      # Creative tools
      "figma"
      "adobe-creative-cloud"
    ];

    casksToRemove = [
      "microsoft-teams"  # Not needed for freelance
      "microsoft-office" # Use alternatives
    ];

    brewsToAdd = [
      "pandoc"  # Document conversion
      "hugo"    # Static site generator
    ];
  };

  system.defaults = {
    screensaver = {
      askForPassword = true;
      askForPasswordDelay = 60;  # Moderate security
    };
  };

  environment.variables = {
    FREELANCE_ENV = "true";
    PROJECTS_DIR = "$HOME/Clients";
  };
}
```

### Example: Gaming Profile

```nix
# hosts/profiles/gaming.nix
{ config, pkgs, lib, ... }:
{
  apps = {
    useBaseLists = true;

    casksToAdd = [
      "steam"
      "discord"
      "obs"
      "battle-net"
    ];

    casksToRemove = [
      "microsoft-office"
      "microsoft-teams"
      "docker"
      "visual-studio-code"
    ];

    systemPackagesToRemove = [
      "terraform"
      "kubectl"
      "helm"
    ];
  };

  # Gaming-optimized settings
  system.defaults.dock.tilesize = lib.mkForce 52;  # Large icons
}
```

## Profile Combinations

### Multiple Profiles

You can combine profiles (though this may lead to conflicts):

```nix
"dual-use-macbook" = mkDarwinSystem {
  hostname = "dual-use";
  machineType = "macbook-pro";
  machineName = "Dual Use MacBook Pro";
  username = "batman";
  extraModules = [
    ./hosts/profiles/work.nix
    ./hosts/profiles/personal.nix
    # Later profiles override earlier ones
    # In this case: personal wins on conflicts
  ];
};
```

**Not recommended:** Better to use host-specific config to cherry-pick from both.

### Profile + Host-Specific

Best practice: Use profile as base, customize in host config:

```nix
# flake.nix
"my-work-laptop" = mkDarwinSystem {
  hostname = "my-work-laptop";
  machineType = "macbook-pro";
  machineName = "My Work Laptop";
  username = "batman";
  extraModules = [
    ./hosts/profiles/work.nix
  ];
};
```

```nix
# hosts/my-work-laptop/default.nix
{ pkgs, config, lib, ... }:
{
  imports = [
    ../macbook-pro/default.nix
  ];

  # The work profile is already applied via extraModules
  # Add additional customizations here:

  apps = {
    useBaseLists = true;

    # Add company-specific tools
    casksToAdd = [
      "microsoft-remote-desktop"  # For work VPN
    ];

    brewsToAdd = [
      "awscli"  # Company uses AWS
    ];
  };

  # Company-specific settings
  system.defaults.screensaver.askForPasswordDelay = lib.mkForce 0;  # Instant lock
}
```

## When to Use Profiles

**Use profiles when:**
- You have multiple machines with similar contexts
- You want to separate work and personal setups
- You need consistent configuration across similar machines
- You want to quickly switch machine contexts

**Use host-specific config when:**
- Only one machine needs these settings
- Configuration is unique to this machine
- Testing before creating a profile
- Very specific hardware/software needs

**Use both when:**
- Profile provides context (work/personal)
- Host config adds machine-specific details

## Profile Priority

Nix applies modules in order:

```
1. shared (base)
2. machine-type (macbook, macmini, etc.)
3. profiles (via extraModules) ← YOU ARE HERE
4. hostname (if exists)
```

Later modules can override earlier ones using:
- **No modifier:** Normal priority
- **`lib.mkDefault`:** Lower priority (can be overridden)
- **`lib.mkForce`:** Higher priority (forces the value)

## Testing Profiles

```bash
# Build with profile
make build HOSTNAME=work-macbook-pro

# Check what's installed
make switch HOSTNAME=work-macbook-pro
brew list --cask | grep -i teams  # Should show microsoft-teams
brew list --cask | grep -i spotify  # Should be absent
```

## Benefits of Profiles

✅ **Reusability:** Define once, use across multiple machines
✅ **Consistency:** All work machines have same work tools
✅ **Maintenance:** Update work profile, all work machines update
✅ **Clarity:** Clear separation between work and personal
✅ **Flexibility:** Easy to switch contexts or combine

## Customization Tips

### Company-Specific Work Profile

Fork the repository and customize work.nix:

```nix
# Add your company's required tools
casksToAdd = [
  "microsoft-teams"
  "slack"
  "your-company-vpn"
  "your-company-security-tool"
];

brewsToAdd = [
  "your-company-cli"
];

environment.variables = {
  COMPANY_NAME = "YourCompany";
  INTERNAL_REGISTRY = "registry.company.com";
};
```

### Hybrid Profile

```nix
# hosts/profiles/hybrid.nix
# For machines that serve dual purposes

{
  apps = {
    useBaseLists = true;

    # Keep both work and personal apps
    casksToAdd = [
      # Work
      "microsoft-teams"
      "slack"

      # Personal
      "spotify"
      "obs"
    ];

    # But remove heavy stuff
    casksToRemove = [
      "adobe-creative-cloud"  # Too heavy
      "vmware-fusion"
    ];
  };

  # Moderate security
  system.defaults.screensaver.askForPasswordDelay = 60;
}
```

## Related Files

- **flake.nix:** Where profiles are applied via `extraModules`
- **hosts/shared/:** Base configuration all profiles build upon
- **hosts/macbook*:** Machine types that profiles enhance
- **modules/darwin/apps/installations.nix:** Base package lists

## Migration Guide

### From No Profile to Work Profile

```bash
# 1. Backup current config
cp flake.nix flake.nix.backup

# 2. Add work profile to your machine in flake.nix
# Change this:
"my-macbook" = mkDarwinSystem {
  hostname = "my-macbook";
  machineType = "macbook";
  # ...
};

# To this:
"my-macbook" = mkDarwinSystem {
  hostname = "my-macbook";
  machineType = "macbook";
  extraModules = [
    ./hosts/profiles/work.nix
  ];
  # ...
};

# 3. Build and apply
make switch

# 4. Verify changes
brew list --cask  # Check for work apps
```

### From Work to Personal Profile

Simply change the extraModules:

```nix
extraModules = [
  # ./hosts/profiles/work.nix
  ./hosts/profiles/personal.nix
];
```

Then rebuild:

```bash
make switch
```

Work apps will be removed, personal apps added.
