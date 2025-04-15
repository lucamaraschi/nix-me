# Nix Me

A comprehensive, modular macOS system configuration using nix-darwin, home-manager, and flakes - inspired by [Mitchell Hashimoto's approach](https://github.com/mitchellh/nixos-config).

## Features

- **Declarative system configuration** for macOS
- **Multi-machine support** with specialized setups for MacBooks and Mac Minis
- **Modular architecture** that separates concerns and promotes reusability
- **Reproducible environment** across multiple machines
- **Automated installation** with a single command
- **Dotfiles management** through Home Manager

## Quick Installation

Install with a single command:

```bash
curl -L https://raw.githubusercontent.com/yourusername/your-nixos-config/main/install.sh | bash
```

Or with custom parameters:

```bash
curl -L https://raw.githubusercontent.com/yourusername/your-nixos-config/main/install.sh | bash -s hostname macbook "Your MacBook Pro"
```

### Installation Parameters

The script accepts the following parameters:
- `hostname`: Computer hostname (e.g., macbook-pro, mac-mini)
- `machine-type`: Either "macbook" or "macmini"
- `machine-name`: User-friendly name for your machine

Examples:
```bash
# For a MacBook Pro
curl -L https://raw.githubusercontent.com/yourusername/your-nixos-config/main/install.sh | bash -s macbook-pro macbook "My MacBook Pro"

# For a Mac Mini
curl -L https://raw.githubusercontent.com/yourusername/your-nixos-config/main/install.sh | bash -s mac-mini macmini "Home Studio Mac Mini"
```

## Directory Structure

```
.
├── flake.nix                 # Entry point with machine configurations
├── Makefile                  # Commands for managing the system
├── install.sh                # Automated installer script
├── hosts/                    # Machine-specific configurations
│   ├── shared/               # Common settings for all machines
│   ├── macbook/              # MacBook-specific optimizations
│   └── macmini/              # Mac Mini-specific optimizations
├── modules/                  # Configuration modules
│   ├── darwin/               # System-level configurations
│   │   ├── apps.nix          # CLI applications
│   │   ├── core.nix          # Core system settings
│   │   ├── fonts.nix         # Font configuration
│   │   ├── homebrew.nix      # GUI applications via Homebrew
│   │   ├── keyboard.nix      # Keyboard settings
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

### Mac Mini Configuration
- Performance optimization
- Multi-display settings
- Desktop-oriented preferences
- Professional/production tools

## Customizing Your Setup

### Adding Applications

#### GUI Applications (via Homebrew)
Edit `modules/darwin/homebrew.nix`:
```nix
homebrew.casks = [
  "visual-studio-code"
  "firefox"
  # Add more applications here
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
Edit `modules/darwin/system.nix` to change macOS system settings.

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

### Common Issues

#### "Nix daemon is not running"
Try restarting the Nix daemon:
```bash
sudo launchctl load /Library/LaunchDaemons/org.nixos.nix-daemon.plist
```

#### "Cannot build derivation"
Check for errors in your Nix files:
```bash
make check
```

#### "Hash mismatch" errors
Update the hash in your configuration to match the one in the error message.

#### "Options don't exist" errors
Make sure you're using options available in your versions of nix-darwin and home-manager.

#### Permission errors
Some operations require sudo privileges. Make sure you have admin access.

## Requirements

- macOS 10.15 Catalina or later
- Administrator privileges
- Internet connection for downloading packages

## Credits

This configuration is inspired by:
- [Mitchell Hashimoto's nixos-config](https://github.com/mitchellh/nixos-config)
- [nix-darwin](https://github.com/LnL7/nix-darwin)
- [home-manager](https://github.com/nix-community/home-manager)

## License

MIT License

---

## Advanced Usage

### Creating a New Machine Configuration

1. Add a configuration to `flake.nix`:
```nix
darwinConfigurations."new-machine" = mkDarwinSystem {
  hostname = "new-machine";
  machineType = "macbook"; # or "macmini"
  machineName = "New MacBook";
};
```

2. Create machine-specific settings if needed:
```bash
mkdir -p hosts/new-machine
touch hosts/new-machine/default.nix
```

3. Build and activate the configuration:
```bash
make HOSTNAME=new-machine switch
```

### Temporarily Testing Changes

Use `make build` instead of `make switch` to build without activating:

```bash
make build
```

### Restoring After Failed Changes

If a configuration breaks your system, restore to the previous generation:

```bash
/run/current-system/sw/bin/darwin-rebuild switch --rollback
```

### Initial Setup on a Fresh Mac

For best results on a fresh macOS installation:

1. Complete basic macOS setup (create user account, connect to Wi-Fi)
2. Open Terminal and run the installation command
3. After installation completes, restart your computer
4. All your applications and settings should be ready to use