# Quick Start: Using Profiles

## What Are Profiles?

Profiles are pre-configured templates that customize your Mac for specific use cases:

- **Work Profile**: Productivity tools, collaboration apps, corporate security settings
- **Personal Profile**: Entertainment, creative tools, relaxed settings
- **Minimal Profile**: Clean slate, add only what you need

## Creating a New Machine with a Profile

### Option 1: Interactive Wizard (Easiest)

```bash
# During fresh install
curl -L https://raw.githubusercontent.com/lucamaraschi/nix-me/main/install.sh | bash

# Or after install
nix-me setup
```

The wizard will ask:
1. **Hostname**: `work-macbook-pro`
2. **Machine Type**: `macbook-pro`
3. **Display Name**: `Work MacBook Pro`
4. **Username**: `yourusername`
5. **Profile**: `work` ← Select here!

### Option 2: Manual Configuration

Add to your `flake.nix`:

```nix
darwinConfigurations = {
  "my-work-mac" = mkDarwinSystem {
    hostname = "my-work-mac";
    machineType = "macbook-pro";
    machineName = "My Work Mac";
    username = "yourusername";
    extraModules = [
      ./hosts/profiles/work.nix  # ← Profile here
    ];
  };
};
```

Then build:
```bash
make switch HOST=my-work-mac
```

## What Each Profile Includes

### Work Profile (`hosts/profiles/work.nix`)

**Adds:**
- Microsoft Teams, Slack, Zoom
- Microsoft Office
- Docker Desktop, VS Code, Postman
- Terraform, kubectl, awscli2

**Removes:**
- Spotify, OBS
- Personal entertainment apps

**Settings:**
- Quick screen lock (5 seconds)
- Disabled analytics
- Work environment variables

### Personal Profile (`hosts/profiles/personal.nix`)

**Adds:**
- Spotify, OBS, Steam
- Adobe Creative Cloud, Figma
- Notion, Todoist
- yt-dlp, ffmpeg

**Removes:**
- Microsoft Teams, Office
- Corporate tools

**Settings:**
- Relaxed screen lock (5 minutes)
- Larger dock (48px)
- Personal environment variables

## Customizing Your Profile

### Per-Machine Overrides

Even with a profile, you can customize individual machines:

```nix
# hosts/my-work-mac/default.nix
{ config, pkgs, lib, ... }:
{
  # Profile: work (from extraModules)

  # But I also need these on THIS machine only
  apps = {
    casksToAdd = [
      "sequel-ace"      # Database tool for this project
      "insomnia"        # Prefer this over Postman
    ];

    casksToRemove = [
      "postman"         # Using Insomnia instead
    ];
  };
}
```

### Creating Your Own Profile

Copy and modify an existing one:

```bash
cp hosts/profiles/work.nix hosts/profiles/myprofile.nix
# Edit as needed
```

Then use it:

```nix
extraModules = [
  ./hosts/profiles/myprofile.nix
];
```

## Combining Profiles

You can layer multiple profiles (later ones override earlier):

```nix
"hybrid-machine" = mkDarwinSystem {
  hostname = "hybrid-machine";
  machineType = "macbook-pro";
  machineName = "Hybrid Machine";
  username = "freelancer";
  extraModules = [
    ./hosts/profiles/work.nix      # Base: work apps
    ./hosts/profiles/personal.nix  # Add: personal apps
    {
      # Fine-tune the combination
      apps.casksToRemove = [
        "microsoft-teams"  # Remove if you don't need it
      ];
    }
  ];
};
```

## Available Machine Types

Combine profiles with any machine type:

- **macbook**: General MacBook (Air/Pro) - battery optimized
- **macbook-pro**: MacBook Pro - performance focused
- **macmini**: Desktop - multi-display, high performance
- **vm**: Virtual Machine - minimal, fast

Example combinations:
- `macbook-pro` + `work` = Work laptop with Pro performance
- `macbook` + `personal` = Personal laptop with battery optimization
- `macmini` + `personal` = Home studio/desktop setup
- `vm` + `minimal` = Clean VM for testing

## Real-World Examples

### Freelancer (Work + Personal)

```bash
# Work machine
"freelance-work" = mkDarwinSystem {
  hostname = "freelance-work";
  machineType = "macbook-pro";
  extraModules = [ ./hosts/profiles/work.nix ];
};

# Personal machine
"freelance-personal" = mkDarwinSystem {
  hostname = "freelance-personal";
  machineType = "macbook";
  extraModules = [ ./hosts/profiles/personal.nix ];
};
```

### Software Engineer

```nix
"dev-machine" = mkDarwinSystem {
  hostname = "dev-machine";
  machineType = "macbook-pro";
  extraModules = [
    ./hosts/profiles/work.nix
    {
      apps.casksToAdd = [
        "tableplus"
        "postman"
        "docker"
      ];
      apps.systemPackagesToAdd = [
        "kubectl"
        "terraform"
        "go"
      ];
    }
  ];
};
```

### Creative Professional

```nix
"creative-studio" = mkDarwinSystem {
  hostname = "creative-studio";
  machineType = "macmini";
  extraModules = [
    ./hosts/profiles/personal.nix
    {
      apps.casksToAdd = [
        "adobe-creative-cloud"
        "final-cut-pro"
        "logic-pro"
      ];
      system.defaults.dock.tilesize = 64; # Big dock for studio
    }
  ];
};
```

## Next Steps

1. **Choose your profile** during wizard setup
2. **Customize** in `hosts/<hostname>/default.nix`
3. **Test**: `make build HOST=<hostname>`
4. **Apply**: `make switch HOST=<hostname>`

See [CUSTOMIZATION.md](../CUSTOMIZATION.md) for advanced topics.
