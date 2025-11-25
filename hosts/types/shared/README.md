# Shared - Universal Base Configuration

**Type:** Base Template for All Machines
**Inherits From:** None (this is the foundation)
**Used By:** All machines (`macbook`, `macbook-pro`, `macmini`, `vm`, and all host-specific configs)

## Overview

This is the foundational configuration layer that provides the complete development environment and standard settings for all machines in the nix-me system. Every machine configuration builds on top of this shared base.

## Purpose

The shared configuration provides:
- **Complete package set:** All CLI tools, GUI apps, and fonts
- **Standard macOS preferences:** Dock, Finder, keyboard, etc.
- **Development environment:** Languages, tools, and utilities
- **User applications:** Communication, productivity, design tools
- **System utilities:** Network tools, file managers, etc.

## Architecture

```
shared/
├── default.nix          # Main shared configuration
└── README.md           # This file
```

The shared configuration is imported as **Layer 1** in every machine:

```
Layer 1: hosts/shared/default.nix        ← You are here
  ↓
Layer 2: hosts/${machineType}/           (macbook, macmini, vm, etc.)
  ↓
Layer 3: hosts/${hostname}/              (optional, host-specific)
  ↓
Layer 4: modules/home-manager/           (user-level configs)
```

## Included Modules

The shared configuration imports from:

```nix
imports = [
  ../../modules/darwin/core.nix
  ../../modules/darwin/system.nix
  ../../modules/darwin/fonts.nix
  ../../modules/darwin/apps
];
```

### Module Breakdown

#### `modules/darwin/core.nix`
- Basic system configuration
- Nix settings and experimental features
- System paths and environment variables

#### `modules/darwin/system.nix`
- macOS system preferences
- Dock configuration
- Finder settings
- Keyboard and trackpad defaults
- Security settings

#### `modules/darwin/fonts.nix`
- System fonts installation
- Developer-friendly monospace fonts
- Icon fonts for terminal use

#### `modules/darwin/apps`
- **installations.nix:** Centralized package management
- **nix-me.nix:** The nix-me CLI tool
- **vm-manager.nix:** VM management utilities
- Other app-specific configurations

## Installed Packages

### System Packages (via Nix)

**Development Tools:**
- **Languages:** nodejs_22, python3, rustup, go
- **Node.js Tools:** pnpm, npm, typescript
- **Version Control:** gh (GitHub CLI)
- **Build Tools:** gcc (via Homebrew)

**File & Text Utilities:**
- **Search:** ripgrep, fd
- **Display:** eza, bat, tree
- **Processing:** jq, pandoc

**System Monitoring:**
- htop (process monitor)
- ncdu (disk usage analyzer)

**Network Tools:**
- nmap (network scanner)
- dnsutils (DNS tools)
- mtr (network diagnostic)

**Utilities:**
- nixpkgs-fmt (Nix formatter)
- comma (command-not-found helper)
- imagemagick (image processing)

### GUI Applications (via Homebrew Casks)

**Communication & Collaboration:**
- Slack
- Microsoft Teams
- Zoom
- Linear
- Loom
- Miro

**Productivity & Utilities:**
- 1Password (password manager)
- Raycast (launcher)
- Rectangle (window manager)
- Hammerspoon (automation)
- HiddenBar (menu bar organizer)
- Proton Mail
- Proton VPN

**Development:**
- Claude Code (AI pair programmer)
- Visual Studio Code
- Ghostty (terminal emulator)
- Docker Desktop
- OrbStack (Docker alternative)
- Orka Desktop (macOS virtualization)
- GitHub Desktop

**Browsers:**
- Google Chrome

**Graphics & Design:**
- Figma
- Adobe Creative Cloud

**Office:**
- Microsoft Office

**Virtualization:**
- UTM (virtual machines)
- VirtualBuddy (macOS VMs)
- VMware Fusion

**Media:**
- Spotify
- OBS (streaming/recording)

### CLI Tools (via Homebrew)

- **System:** coreutils, direnv, gcc, grep, trash
- **Development:** git, terraform, helm, k3d
- **Utilities:** fd, jq, mas (Mac App Store CLI), ripgrep

### Mac App Store Apps

- **Tailscale** (VPN mesh networking) - 1475387142
- **Xcode** (Apple development tools) - 497799835
- **iA Writer** (markdown editor) - 775737590

### Fonts

Installed via `modules/darwin/fonts.nix`:
- SF Mono (Apple's monospace font)
- Fira Code (coding font with ligatures)
- JetBrains Mono
- Other developer-friendly fonts

## System Preferences

### Dock
- **Auto-hide:** Enabled
- **Show recent applications:** Disabled
- **Minimize windows into application icon:** Enabled
- **Icon size:** Set by machine type (32px for MacBook, 36px for MacBook Pro, etc.)
- **Minimize animation:** Genie effect
- **Show indicators for open applications:** Enabled

### Finder
- **Show hidden files:** Enabled
- **Show all file extensions:** Enabled
- **Show path bar:** Enabled
- **Show status bar:** Enabled
- **Default view:** Column view
- **Search scope:** Current folder
- **Disable warnings:** When changing file extensions

### Keyboard & Input
- **Key repeat rate:** Fast
- **Initial key repeat delay:** Short
- **Disable automatic capitalization**
- **Disable automatic period substitution**
- **Disable smart quotes and dashes**

### Trackpad (MacBook only)
- **Tap to click:** Enabled
- **Two-finger right click:** Enabled
- **Natural scrolling:** Enabled

### Security
- **Gatekeeper:** Enabled (except in VMs)
- **Firewall:** Configured
- **FileVault:** Recommended (not forced)

## Home Manager Integration

The shared configuration automatically integrates Home Manager for user-level configurations:

**Included:**
- Fish shell with custom functions
- Git configuration with aliases
- SSH with 1Password integration
- VS Code settings
- Ghostty terminal config
- Tmux configuration
- Rectangle window manager settings

See `modules/home-manager/` for details.

## Customization Philosophy

The shared configuration is designed with the **inheritance model**:

1. **Define comprehensive base** (this layer)
2. **Override or extend** in machine-type layers (macbook, macmini, etc.)
3. **Fine-tune** in host-specific layers (nabucodonosor, bellerofonte, etc.)

### Adding Packages Globally

Edit `modules/darwin/apps/installations.nix`:

```nix
baseLists = {
  systemPackages = [
    # Add your Nix package here
    "new-cli-tool"
  ];

  casks = [
    # Add your GUI app here
    "new-gui-app"
  ];

  brews = [
    # Add your Homebrew formula here
    "new-brew-tool"
  ];
};
```

### Removing Packages Per-Machine

In your host-specific config:

```nix
apps = {
  useBaseLists = true;

  casksToRemove = [ "obs" "spotify" ];  # Remove from this machine
  brewsToRemove = [ "terraform" ];
  systemPackagesToRemove = [ "go" ];
};
```

## Environment Variables

Set globally for all machines:

```nix
environment.variables = {
  EDITOR = "vim";
  VISUAL = "vim";
};
```

Override in machine-specific configs if needed.

## System PATH

```nix
environment.systemPath = [ "/opt/homebrew/bin" ];
environment.pathsToLink = [ "/Applications" ];
```

Ensures Homebrew and applications are available system-wide.

## When to Modify Shared Config

**Modify shared when:**
- Adding a tool/app that ALL machines should have
- Changing a default that applies universally
- Adding a new font everyone needs
- Updating base system preferences

**Don't modify shared when:**
- Adding machine-specific tools (use host config)
- Changing settings for just one machine type
- Testing new packages (test in host config first)
- Personalizing for individual users (use home-manager)

## Relationship to Other Layers

```
shared (Layer 1)
├── Provides: Base packages, system settings, defaults
├── Cannot: Override machine-type specifics
└── Priority: Lowest (can be overridden by mkDefault, mkForce)

machine-type (Layer 2)
├── Inherits: Everything from shared
├── Adds: Type-specific optimizations (battery, performance, etc.)
├── Can override: Shared defaults with mkDefault or mkForce
└── Examples: macbook, macbook-pro, macmini, vm

hostname (Layer 3)
├── Inherits: Everything from shared + machine-type
├── Adds: Host-specific packages and settings
├── Can override: Both shared and machine-type settings
└── Examples: nabucodonosor, bellerofonte, gotham

home-manager (Layer 4)
├── Runs: After all system configs
├── Manages: User-level dotfiles and apps
├── Cannot: Change system settings (only user settings)
└── Location: modules/home-manager/
```

## Package Statistics

**Total Base Packages:**
- Nix packages: ~33
- Homebrew casks (GUI): ~30
- Homebrew brews (CLI): ~13
- Mac App Store apps: 3
- **Total: ~79 packages**

**Disk Space:**
- Nix store: ~1-3GB (shared across packages)
- Homebrew casks: ~5-15GB (varies by app)
- Total estimated: ~6-18GB

## Performance Impact

- **Build time:** ~5-15 minutes (first build)
- **Rebuild time:** ~1-3 minutes (incremental)
- **Memory usage:** No runtime overhead (packages only used when launched)
- **Startup time:** No impact (nix-darwin doesn't run at boot)

## Related Files

- **flake.nix:** Defines how shared is loaded for each machine
- **modules/darwin/apps/installations.nix:** Package definitions
- **modules/darwin/system.nix:** System preference settings
- **modules/home-manager/:** User-level configurations

## Migration Path

If you want to try nix-me starting from this shared config:

1. Fork the repository
2. Review `modules/darwin/apps/installations.nix` packages
3. Remove unwanted packages from base lists
4. Create your machine config in `flake.nix`
5. Run `./install.sh`

Or use the inheritance model:
1. Keep shared as-is (complete base)
2. Create host-specific config with `casksToRemove`, `brewsToRemove`
3. Only install what you need per machine

## Philosophy

The shared configuration embodies the **"complete by default, minimal by override"** philosophy:

- Start with a comprehensive, opinionated base
- Every machine gets a full development environment
- Customize by subtraction (remove what you don't need)
- Or customize by addition (add what you need)
- Never modify the base for host-specific needs

This ensures:
- ✅ Consistency across machines
- ✅ Easy onboarding (everything just works)
- ✅ Reproducibility (same base everywhere)
- ✅ Flexibility (override anything per-machine)
