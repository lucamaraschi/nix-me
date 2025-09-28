# nix-me

A comprehensive, modular macOS system configuration using nix-darwin, home-manager, and flakes - inspired by [Mitchell Hashimoto's approach](https://github.com/mitchellh/nixos-config).

## Features

- 🍎 **Declarative system configuration** for macOS
- 💻 **Multi-machine support** with specialized setups for MacBooks, Mac Minis, and VMs
- 🧩 **Modular architecture** that separates concerns and promotes reusability
- 🔄 **Reproducible environment** across multiple machines
- 🚀 **Automated installation** with robust error handling and recovery
- 📁 **Dotfiles management** through Home Manager
- 📦 **Flexible package management** with add/remove inheritance system

## Quick Start

### One-Command Installation

```bash
# Quick install (auto-detects everything)
curl -L https://raw.githubusercontent.com/lucamaraschi/nix-me/main/install.sh | bash
```

### Custom Installation Examples

```bash
# MacBook Pro with custom name
curl -L https://raw.githubusercontent.com/lucamaraschi/nix-me/main/install.sh | bash -s macbook-pro macbook "My MacBook Pro"

# Mac Mini workstation
curl -L https://raw.githubusercontent.com/lucamaraschi/nix-me/main/install.sh | bash -s mac-mini macmini "Studio Mac Mini"

# Force reinstall if something went wrong
curl -L https://raw.githubusercontent.com/lucamaraschi/nix-me/main/install.sh | FORCE_NIX_REINSTALL=1 bash

# Non-interactive for automation
curl -L https://raw.githubusercontent.com/lucamaraschi/nix-me/main/install.sh | NON_INTERACTIVE=1 bash
```

### Installation Parameters

The script accepts the following parameters:

- **hostname**: Computer hostname (e.g., `macbook-pro`, `mac-mini`)
- **machine-type**: Either `"macbook"`, `"macmini"`, or `"vm"`
- **machine-name**: User-friendly name for your machine

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

## Repository Structure

```
.
├── flake.nix                   # Entry point with machine configurations
├── Makefile                    # Commands for managing the system
├── install.sh                  # Automated installer script with recovery
├── hosts/                      # Machine-specific configurations
│   ├── shared/                 # Common settings for all machines
│   ├── macbook/               # MacBook-specific optimizations
│   ├── macmini/               # Mac Mini-specific optimizations
│   └── vm/                    # Virtual machine optimizations
├── modules/                   # Configuration modules
│   ├── darwin/                # System-level configurations
│   │   ├── apps.nix           # CLI applications
│   │   ├── core.nix           # Core system settings
│   │   ├── fonts.nix          # Font configuration
│   │   ├── homebrew.nix       # GUI applications via Homebrew
│   │   ├── keyboard.nix       # Keyboard settings
│   │   ├── shell.nix          # Shell configuration
│   │   └── system.nix         # macOS system preferences
│   └── home-manager/          # User-level configurations
│       ├── default.nix        # Main home configuration
│       ├── fish.nix           # Fish shell configuration
│       ├── git.nix            # Git configuration
│       ├── tmux.nix           # Tmux terminal multiplexer
│       └── vscode.nix         # VS Code configuration
└── overlays/                  # Custom package modifications
    └── nodejs.nix             # Node.js configuration
```

## System Management

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

## Machine-Specific Optimizations

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

## Package Management

This configuration uses an intelligent inheritance system for managing packages:

```nix
# hosts/macbook/default.nix
homebrew = {
  useBaseLists = true; # Enable inheritance mode

  # Remove packages that are too heavy for laptops
  casksToRemove = [
    "adobe-creative-cloud" # Too resource-heavy
    "vmware-fusion" # VM not needed on laptop
    "obs" # Streaming software
  ];

  # Add laptop-specific packages
  casksToAdd = [
    "coconutbattery" # Battery health monitoring
    "amphetamine" # Prevent sleep during presentations
  ];

  # Same pattern for brews and MAS apps
  brewsToRemove = ["terraform" "helm"];
  brewsToAdd = ["battery" "wifi-password"];

  masAppsToRemove = ["Xcode"]; # Too large for laptop
  masAppsToAdd = {
    "Tot" = 1491071483; # Quick notes
  };
};
```

## Customization

### Adding Applications

Edit your machine-specific config or `modules/darwin/homebrew.nix`:

```nix
casksToAdd = [
  "new-application"
  "another-app"
];
```

### Adding CLI Tools

Edit `modules/darwin/apps.nix`:

```nix
environment.systemPackages = with pkgs; [
  ripgrep
  fd
  # Add more CLI tools here
];
```

### System Settings

Edit `modules/darwin/system.nix` to change macOS system settings. The configuration uses `lib.mkDefault` for all settings, allowing machine-specific overrides.

### User Configuration

Edit files in `modules/home-manager/` to modify:

- Shell configuration (`fish.nix`)
- Git settings (`git.nix`)
- Editor preferences (`vscode.nix`)
- Terminal setup (`tmux.nix`)

## Updates

To update your Nix packages and apply changes:

```bash
make update switch
```

This will:

- Update all Nix packages to their latest versions
- Build the new system configuration
- Switch to the new configuration

## Troubleshooting

### System Recovery

If Nix gets into a broken state:

```bash
# Force complete reinstall
FORCE_NIX_REINSTALL=1 ./install.sh

# Non-interactive mode for automation
NON_INTERACTIVE=1 FORCE_NIX_REINSTALL=1 ./install.sh
```

### Repository Conflicts

If the repository has been rebased or force-pushed:

```bash
# The install script automatically handles this by:
# 1. Stashing local changes
# 2. Creating backup branches for local commits
# 3. Force resetting to remote state
./install.sh # Safe to re-run
```

### VM Issues

For virtual machines:

```bash
# Skip Homebrew for lighter installation
SKIP_BREW_ON_VM=1 ./install.sh
```

### Daemon Issues

The installer automatically detects and fixes daemon issues:

```bash
# Try the installer recovery
./install.sh

# Or manually restart
sudo launchctl load /Library/LaunchDaemons/org.nixos.nix-daemon.plist
```

### Configuration Errors

```bash
# Check for errors in your Nix files
make check

# Complete system recovery
FORCE_NIX_REINSTALL=1 NON_INTERACTIVE=1 ./install.sh

# Restore to previous generation
/run/current-system/sw/bin/darwin-rebuild switch --rollback

# Rebuild without switching (test)
make build
```

## Requirements

- macOS 10.15 Catalina or later
- Administrator privileges
- Internet connection for downloading packages
- At least 5GB free disk space for Nix store

## Adding New Machines

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

## Automation & CI/CD

For multiple machines or CI/CD:

```bash
# Automated installation
NON_INTERACTIVE=1 \
HOSTNAME=production-mini \
MACHINE_TYPE=macmini \
MACHINE_NAME="Production Mac Mini" \
./install.sh

# Test build without applying
make build

# Test in VM first
make MACHINE_TYPE=vm build

# Dry run
make DRY_RUN=1 switch
```

## Example Configurations

### Photography Workstation

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
    ];
    masAppsToAdd = {
      "Affinity Photo" = 824183456;
      "Pixelmator Pro" = 1289583905;
    };
  };
}
```

### Development Laptop

```nix
# hosts/dev-laptop/default.nix
{ pkgs, config, lib, ... }:
{
  homebrew = {
    useBaseLists = true;
    # Remove heavy applications
    casksToRemove = [
      "adobe-creative-cloud" "microsoft-office"
    ];
    # Keep only essential dev tools
    casksToAdd = [
      "postman" "tableplus" "dash"
    ];
    brewsToAdd = [
      "httpie" "jq" "yq" "gh"
    ];
  };
}
```

## FAQ

### Is this safe to use on my existing Mac?

Yes! This setup:

- Uses Homebrew for GUI applications (casks)
- Uses Nix for CLI tools and system packages
- Uses Mac App Store for iOS/macOS specific apps
- Doesn't interfere with manually installed software

The installer:

- Backs up existing configurations before modifying
- Preserves your current applications (they just won't be managed)
- Stashes any local changes to the config repository
- Creates rollback points so you can revert if needed

### How do I uninstall?

```bash
# Uninstall nix-darwin (returns to stock macOS)
sudo /nix/var/nix/profiles/system/sw/bin/darwin-uninstaller

# Completely remove Nix (optional)
sudo /nix/uninstall

# Remove configuration directory (optional)
rm -rf ~/.config/nixpkgs
```

### Performance Impact

- Minimal runtime overhead - Nix only active during builds/updates
- Storage usage - ~1-5GB for Nix store (shared between packages)
- Memory usage - No additional RAM usage during normal operation
- Network - Only downloads during updates

### Backup & Restore

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

## Compatibility

- macOS 10.15 Catalina and later
- Intel and Apple Silicon Macs supported
- Virtual machines (UTM, VMware, Parallels) supported
- Regular testing on latest macOS versions

## License

MIT License

## Inspiration

This configuration is inspired by:

- [Mitchell Hashimoto's nixos-config](https://github.com/mitchellh/nixos-config)
- [nix-darwin](https://github.com/LnL7/nix-darwin)
- [Home Manager](https://github.com/nix-community/home-manager)

## Contributing

- Fork the repository
- Customize for your needs
- Test changes with `make build`
- Apply with `make switch`
- Share improvements via pull requests
