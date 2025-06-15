# Nix Me

A comprehensive, modular macOS system configuration using nix-darwin, home-manager, and flakes - inspired by [Mitchell Hashimoto's approach](https://github.com/mitchellh/nixos-config).

## Features

- **Declarative system configuration** for macOS
- **Multi-machine support** with specialized setups for MacBooks, Mac Minis, and VMs
- **Modular architecture** that separates concerns and promotes reusability
- **Reproducible environment** across multiple machines
- **Automated installation** with robust error handling and recovery
- **Dotfiles management** through Home Manager
- **Flexible package management** with add/remove inheritance system

## Quick Installation

Install with a single command:

```bash
curl -L https://raw.githubusercontent.com/lucamaraschi/nix-me/main/install.sh | bash
```

Or with custom parameters:

```bash
curl -L https://raw.githubusercontent.com/lucamaraschi/nix-me/main/install.sh | bash -s hostname macbook "Your MacBook Pro"
```

### Ready-to-use Installation Commands

```bash
# Quick install (auto-detects everything)
curl -L https://raw.githubusercontent.com/lucamaraschi/nix-me/main/install.sh | bash

# MacBook Pro with custom name
curl -L https://raw.githubusercontent.com/lucamaraschi/nix-me/main/install.sh | bash -s macbook-pro macbook "My MacBook Pro"

# Mac Mini workstation
curl -L https://raw.githubusercontent.com/lucamaraschi/nix-me/main/install.sh | bash -s mac-mini macmini "Studio Mac Mini"

# Force reinstall if something went wrong
FORCE_NIX_REINSTALL=1 curl -L https://raw.githubusercontent.com/lucamaraschi/nix-me/main/install.sh | bash

# Non-interactive for automation
NON_INTERACTIVE=1 curl -L https://raw.githubusercontent.com/lucamaraschi/nix-me/main/install.sh | bash
```

### Installation Parameters

The script accepts the following parameters:
- `hostname`: Computer hostname (e.g., macbook-pro, mac-mini)
- `machine-type`: Either "macbook", "macmini", or "vm"
- `machine-name`: User-friendly name for your machine

Examples:
```bash
# For a MacBook Pro
curl -L https://raw.githubusercontent.com/lucamaraschi/nix-me/main/install.sh | bash -s macbook-pro macbook "My MacBook Pro"

# For a Mac Mini
curl -L https://raw.githubusercontent.com/lucamaraschi/nix-me/main/install.sh | bash -s mac-mini macmini "Home Studio Mac Mini"

# For a VM (auto-detected)
curl -L https://raw.githubusercontent.com/lucamaraschi/nix-me/main/install.sh | bash -s vm-test vm "Test VM"
```

### Environment Variables

Control installation behavior with environment variables:

```bash
# Force complete Nix reinstall (useful for recovery)
FORCE_NIX_REINSTALL=1 ./install.sh

# Skip confirmation prompts (for automation)
NON_INTERACTIVE=1 ./install.sh

# Skip Homebrew on VMs (lighter installation)
SKIP_BREW_ON_VM=1 ./install.sh

# Combine multiple options
FORCE_NIX_REINSTALL=1 NON_INTERACTIVE=1 ./install.sh macbook-pro macbook "Development MacBook"
```

## Directory Structure

```
.
├── flake.nix                 # Entry point with machine configurations
├── Makefile                  # Commands for managing the system
├── install.sh                # Automated installer script with recovery
├── hosts/                    # Machine-specific configurations
│   ├── shared/               # Common settings for all machines
│   ├── macbook/              # MacBook-specific optimizations
│   ├── macmini/              # Mac Mini-specific optimizations
│   └── vm/                   # Virtual machine optimizations
├── modules/                  # Configuration modules
│   ├── darwin/               # System-level configurations
│   │   ├── apps.nix          # CLI applications
│   │   ├── core.nix          # Core system settings
│   │   ├── fonts.nix         # Font configuration
│   │   ├── homebrew.nix      # GUI applications via Homebrew
│   │   ├── keyboard.nix      # Keyboard settings
│   │   ├── shell.nix         # Shell configuration
│   │   └── system.nix        # macOS system preferences
│   └── home-manager/         # User-level configurations
│       ├── default.nix       # Main home configuration
│       ├── fish.nix          # Fish shell configuration
│       ├── git.nix           # Git configuration
│       ├── tmux.nix          # Tmux terminal multiplexer
│       └── vscode.nix        # VS Code configuration
└── overlays/                 # Custom package modifications
    └── nodejs.nix            # Node.js configuration
```

## After Installation

Once the installation completes, you can manage your system with:

```bash
# Apply changes after updating configuration files
make switch

# Update packages and apply configuration
make update switch

# Check configuration validity
make check

# See all available commands
make help
```

## Machine-Specific Configurations

This setup includes optimizations specific to different Mac types:

### MacBook Configuration
- Trackpad optimization
- Battery preservation settings
- Power management settings
- Portable-friendly apps
- Smaller dock icons for screen space

### Mac Mini Configuration
- Performance optimization
- Multi-display settings
- Desktop-oriented preferences
- Professional/production tools
- Larger dock icons for desktop use

### VM Configuration
- Minimal package set
- Disabled problematic features
- Optimized for virtual environments
- Reduced resource usage

## Customizing Your Setup

### Package Management with Inheritance

This configuration uses an intelligent inheritance system for managing packages:

```nix
# hosts/macbook/default.nix
homebrew = {
  useBaseLists = true;  # Enable inheritance mode
  
  # Remove packages that are too heavy for laptops
  casksToRemove = [
    "adobe-creative-cloud"   # Too resource-heavy
    "vmware-fusion"          # VM not needed on laptop
    "obs"                    # Streaming software
  ];
  
  # Add laptop-specific packages
  casksToAdd = [
    "coconutbattery"         # Battery health monitoring
    "amphetamine"            # Prevent sleep during presentations
  ];
  
  # Same pattern for brews and MAS apps
  brewsToRemove = ["terraform" "helm"];
  brewsToAdd = ["battery" "wifi-password"];
  
  masAppsToRemove = ["Xcode"];  # Too large for laptop
  masAppsToAdd = {
    "Tot" = 1491071483;         # Quick notes
  };
};
```

### Adding Applications

#### GUI Applications (via Homebrew)
Edit your machine-specific config or `modules/darwin/homebrew.nix`:
```nix
casksToAdd = [
  "new-application"
  "another-app"
];
```

#### CLI Tools (via Nix)
Edit `modules/darwin/apps.nix`:
```nix
environment.systemPackages = with pkgs; [
  ripgrep
  fd
  # Add more CLI tools here
];
```

### Modifying System Preferences
Edit `modules/darwin/system.nix` to change macOS system settings. The configuration uses `lib.mkDefault` for all settings, allowing machine-specific overrides.

### Updating User Configuration
Edit files in `modules/home-manager/` to modify:
- Shell configuration (fish.nix)
- Git settings (git.nix)
- Editor preferences (vscode.nix)
- Terminal setup (tmux.nix)

## Updating

To update your Nix packages and apply changes:

```bash
make update switch
```

This will:
1. Update all Nix packages to their latest versions
2. Build the new system configuration
3. Switch to the new configuration

## Troubleshooting

### Installation Issues

#### Broken or Incomplete Nix Installation
If Nix gets into a broken state (interrupted installation, corrupted files):

```bash
# Force complete reinstall
FORCE_NIX_REINSTALL=1 ./install.sh

# Non-interactive mode for automation
NON_INTERACTIVE=1 FORCE_NIX_REINSTALL=1 ./install.sh
```

#### Git Repository Conflicts
If the repository has been rebased or force-pushed:

```bash
# The install script automatically handles this by:
# 1. Stashing local changes
# 2. Creating backup branches for local commits  
# 3. Force resetting to remote state
./install.sh  # Safe to re-run
```

#### VM Installation Issues
For virtual machines:

```bash
# Skip Homebrew for lighter installation
SKIP_BREW_ON_VM=1 ./install.sh

# VM-specific configuration is auto-created
```

### Common Issues

#### "Nix daemon is not running"
The installer now automatically detects and fixes daemon issues:

```bash
# Try the installer recovery
./install.sh

# Or manually restart
sudo launchctl load /Library/LaunchDaemons/org.nixos.nix-daemon.plist
```

#### "Cannot build derivation"
Check for errors in your Nix files:
```bash
make check
```

#### Permission errors
Ensure you have admin access and run with sudo when prompted.

#### Configuration conflicts
The new architecture prevents most conflicts by using `lib.mkDefault` in base configurations.

### Recovery Commands

```bash
# Complete system recovery
FORCE_NIX_REINSTALL=1 NON_INTERACTIVE=1 ./install.sh

# Restore to previous generation
/run/current-system/sw/bin/darwin-rebuild switch --rollback

# Check what changed
make check

# Rebuild without switching (test)
make build
```

## Requirements

- macOS 10.15 Catalina or later
- Administrator privileges
- Internet connection for downloading packages
- At least 5GB free disk space for Nix store

## Advanced Usage

### Creating a New Machine Configuration

1. Add a configuration to `flake.nix`:
```nix
darwinConfigurations."new-machine" = mkDarwinSystem {
  hostname = "new-machine";
  machineType = "macbook"; # or "macmini" or "vm"
  machineName = "New MacBook";
};
```

2. Create machine-specific settings if needed:
```bash
mkdir -p hosts/new-machine
touch hosts/new-machine/default.nix
```

3. Build and activate:
```bash
make HOSTNAME=new-machine switch
```

### Automated Deployment

For multiple machines or CI/CD:

```bash
# Automated installation
NON_INTERACTIVE=1 \
HOSTNAME=production-mini \
MACHINE_TYPE=macmini \
MACHINE_NAME="Production Mac Mini" \
./install.sh
```

### Configuration Testing

```bash
# Test build without applying
make build

# Test in VM first
make MACHINE_TYPE=vm build

# Dry run
make DRY_RUN=1 switch
```

## Credits

This configuration is inspired by:
- [Mitchell Hashimoto's nixos-config](https://github.com/mitchellh/nixos-config)
- [nix-darwin](https://github.com/LnL7/nix-darwin)
- [home-manager](https://github.com/nix-community/home-manager)
- [Determinate Systems Nix Installer](https://github.com/DeterminateSystems/nix-installer)

## License

MIT License

---

## FAQ

### Why use Nix on macOS?
- **Reproducible environments** across multiple machines
- **Declarative configuration** - your entire system is code
- **Atomic upgrades/rollbacks** - safe to experiment
- **Isolation** - packages don't interfere with each other
- **Extensive package repository** - 100k+ packages available

### How is this different from other dotfiles managers?
- **System-level configuration** - manages macOS settings, not just dotfiles
- **Package management** - installs and manages applications
- **Multi-machine support** - different configs for different machine types
- **Inheritance system** - easily customize packages per machine
- **Atomic operations** - all-or-nothing updates

### Can I use this alongside existing package managers?
Yes! This setup:
- Uses **Homebrew** for GUI applications (casks)
- Uses **Nix** for CLI tools and system packages
- Uses **Mac App Store** for iOS/macOS specific apps
- Doesn't interfere with manually installed software

### What happens to my existing configuration?
The installer:
- **Backs up** existing configurations before modifying
- **Preserves** your current applications (they just won't be managed)
- **Stashes** any local changes to the config repository
- **Creates rollback points** so you can revert if needed

### How do I uninstall everything?
```bash
# Uninstall nix-darwin (returns to stock macOS)
sudo /nix/var/nix/profiles/system/sw/bin/darwin-uninstaller

# Completely remove Nix (optional)
sudo /nix/uninstall

# Remove configuration directory (optional)
rm -rf ~/.config/nixpkgs
```

### Can I use this in corporate environments?
Yes, with considerations:
- **Admin privileges** required for initial setup
- **Network access** needed for downloading packages
- **Policies** - check if your company allows package managers
- **Compliance** - all packages are from official repositories

### How do I contribute or modify this configuration?
1. **Fork** the repository
2. **Customize** for your needs
3. **Test** changes with `make build`
4. **Apply** with `make switch`
5. **Share** improvements via pull requests

### Performance impact?
- **Minimal runtime overhead** - Nix only active during builds/updates
- **Storage usage** - ~1-5GB for Nix store (shared between packages)
- **Memory usage** - No additional RAM usage during normal operation
- **Network** - Only downloads during updates

### Backup and restore?
Your entire system configuration is in git, so:

```bash
# Backup = commit your changes
git add . && git commit -m "My customizations"
git push

# Restore = clone and install
git clone your-fork.git ~/.config/nixpkgs
cd ~/.config/nixpkgs
./install.sh
```

### Supported macOS versions?
- **macOS 10.15 Catalina** and later
- **Intel and Apple Silicon** Macs supported
- **Virtual machines** (UTM, VMware, Parallels) supported
- **Regular testing** on latest macOS versions

## Architecture Details

### Configuration Hierarchy

The configuration uses a layered approach with proper precedence:

1. **`modules/darwin/system.nix`** - Base defaults with `lib.mkDefault`
2. **`hosts/shared/default.nix`** - Overrides for most machines  
3. **`hosts/macbook/default.nix`** - MacBook-specific overrides
4. **`hosts/macmini/default.nix`** - Mac Mini-specific overrides
5. **`hosts/vm/default.nix`** - VM-specific overrides

This allows clean customization without conflicts.

### Package Inheritance System

The Homebrew configuration supports sophisticated package management:

```nix
# Base packages defined in modules/darwin/homebrew.nix
# Machine configs can:
useBaseLists = true;           # Enable inheritance
casksToRemove = ["app1"];      # Remove from base list  
casksToAdd = ["app2"];         # Add to base list
brewsToRemove = ["tool1"];     # Remove CLI tools
brewsToAdd = ["tool2"];        # Add CLI tools  
masAppsToRemove = ["App"];     # Remove Mac App Store apps
masAppsToAdd = { "App" = 123; }; # Add Mac App Store apps
```

### Error Recovery

The installer includes comprehensive error recovery:

- **Incomplete installations** - Detects and fixes partial installs
- **Corrupted Nix** - Automatically uninstalls and reinstalls
- **Git conflicts** - Safely handles repository changes
- **Permission issues** - Guides through sudo requirements
- **Network failures** - Retryable with resume capability

### Virtual Machine Support

Special handling for VM environments:

- **Auto-detection** of VM platforms (UTM, VMware, Parallels)
- **Minimal package sets** to reduce resource usage
- **Disabled problematic features** that don't work in VMs
- **Skip heavy applications** like development tools

## Customization Examples

### Example: Photography Workstation (Mac Mini)

```nix
# hosts/photo-station/default.nix
{ pkgs, config, lib, ... }:
{
  homebrew = {
    useBaseLists = true;
    
    # Remove development tools
    casksToRemove = [
      "docker" "visual-studio-code" "github"
    ];
    
    # Add photography apps
    casksToAdd = [
      "adobe-lightroom" "adobe-photoshop" 
      "capture-one" "luminar-ai"
      "image2icon" "exifrenamer"
    ];
    
    masAppsToAdd = {
      "Affinity Photo" = 824183456;
      "Pixelmator Pro" = 1289583905;
    };
  };
  
  # Photography-optimized system settings
  system.defaults = {
    NSGlobalDomain.AppleShowAllExtensions = true;
    finder.CreateDesktop = true; # Show files on desktop
  };
}
```

### Example: Minimal Developer Laptop

```nix
# hosts/dev-laptop/default.nix  
{ pkgs, config, lib, ... }:
{
  homebrew = {
    useBaseLists = true;
    
    # Remove heavy applications
    casksToRemove = [
      "adobe-creative-cloud" "microsoft-office"
      "obs" "spotify" # Use web versions
    ];
    
    # Keep only essential dev tools
    casksToAdd = [
      "postman" "tableplus" "dash"
    ];
    
    # Lightweight CLI tools
    brewsToAdd = [
      "httpie" "jq" "yq" "gh"
    ];
  };
  
  # Power-saving settings
  system.activationScripts.devOptimization.text = ''
    pmset -b displaysleep 10  # Aggressive power saving
    pmset -c displaysleep 30
  '';
}
```

This configuration provides a solid foundation for any macOS setup while remaining flexible and maintainable!