# nix-me

Declarative macOS configuration with nix-darwin, home-manager, and an interactive setup experience.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Nix](https://img.shields.io/badge/Built%20with-Nix-5277C3.svg?logo=nixos&logoColor=white)](https://nixos.org)
[![macOS](https://img.shields.io/badge/macOS-10.15+-000000?logo=apple&logoColor=white)](https://www.apple.com/macos/)

## What is nix-me?

nix-me is a comprehensive macOS system configuration that lets you manage your entire development environment as code. It features an interactive setup wizard and CLI tool that makes Nix approachable for everyone.

**Key Features:**

- Interactive setup wizard - no Nix knowledge required
- TUI Configuration Inspector - visualize your system configuration
- CLI tool for ongoing customization (`nix-me`)
- Multi-machine support (MacBooks, Mac Minis, VMs)
- Reproducible environments across machines
- Fish shell with custom functions and integrations
- 1Password SSH integration
- Modular architecture with inheritance system
- Unified package management (Nix + Homebrew)

## Quick Start

### Interactive Installation (Recommended)

The interactive wizard walks you through setup step-by-step:

```bash
curl -L https://raw.githubusercontent.com/lucamaraschi/nix-me/main/install.sh | bash
```

The wizard will:

1. Detect existing machine configurations (if any)
2. Let you create a new machine or modify an existing one
3. Guide you through configuration options
4. Optionally let you search and add packages interactively

**Time required:** 30-60 minutes (depending on internet speed)

### Prerequisites

Before starting:

- macOS 10.15+ with admin privileges
- At least 5GB free disk space
- Stable internet connection
- Your macOS username (run `whoami` to check)

### What Gets Installed

The configuration will install:

- **Nix package manager** (~5-10 minutes)
- **nix-darwin** for system management
- **Fish shell** with custom configurations
- **CLI tools** via Nix
- **GUI apps** via Homebrew (~15-30 minutes)
- **macOS system preferences**

## Post-Install: Using nix-me

After installation, the `nix-me` command is available for managing your system:

### Common Commands

```bash
# Interactive customization menu
nix-me customize

# Configuration inspector (view packages, files, dependencies)
nix-me inspect

# Search and add a GUI application
nix-me add app spotify

# Add a CLI tool
nix-me add tool jq

# Check system health
nix-me doctor

# View installed packages
nix-me list

# Apply configuration changes
nix-me switch

# Update all packages
nix-me update
```

### Interactive Wizard

Run the wizard again to:

- Modify existing machine configurations
- Change username, machine type, or name
- Add/remove packages interactively

```bash
nix-me setup
```

The wizard will detect existing machines and let you choose what to modify.

## Repository Structure

```
nix-me/
├── flake.nix                      # Machine definitions
├── Makefile                       # Build commands
├── install.sh                     # Interactive installer
│
├── lib/                           # Wizard & CLI libraries
│   ├── ui.sh                      # Terminal UI components
│   ├── wizard.sh                  # Interactive setup wizard
│   ├── config-builder.sh          # Configuration generator
│   └── vm-manager.sh              # VM management
│
├── bin/
│   └── nix-me                     # CLI tool
│
├── tui/                           # Interactive TUI (React Ink)
│   ├── src/
│   │   └── components/
│   │       └── ConfigInspector.tsx # Configuration inspector
│   └── package.json
│
├── hosts/                         # Machine-specific configs
│   ├── shared/                    # Common settings for all machines
│   ├── macbook/                   # MacBook optimizations
│   ├── macbook-pro/               # MacBook Pro optimizations
│   ├── macmini/                   # Mac Mini optimizations
│   ├── vm/                        # VM optimizations
│   ├── profiles/                  # Work/Personal profiles
│   └── [hostname]/                # Your specific machines
│
└── modules/
    ├── darwin/                    # System-level configs
    │   ├── apps/
    │   │   ├── installations.nix  # Unified package management
    │   │   ├── nix-me.nix         # nix-me CLI
    │   │   ├── vm-manager.nix     # VM management tools
    │   │   └── ...
    │   ├── core.nix               # Core system settings
    │   ├── system.nix             # macOS preferences
    │   ├── fonts.nix              # Font configuration
    │   └── ...
    │
    ├── home-manager/              # User-level configs
    │   ├── apps/                  # User applications
    │   ├── shell/                 # Shell configurations
    │   │   └── fish.nix           # Fish shell setup
    │   ├── rectangle.nix          # Window manager
    │   ├── git.nix                # Git settings
    │   ├── ssh.nix                # SSH + 1Password
    │   └── ...
    │
    └── shared/                    # Shared between Darwin & NixOS
        ├── fish-base.nix          # Base Fish configuration
        └── packages.nix           # Common package definitions
```

## Configuration Inspector

The TUI Configuration Inspector helps you understand your system setup:

```bash
# Launch the inspector
nix-me inspect

# Or from the project directory
npm --prefix tui run dev
```

**Features:**

- **Package Browser** - View all installed packages organized by source:
  - Homebrew Formulas (CLI tools)
  - Homebrew Casks (GUI applications)
  - Nix packages

- **File Browser** - Navigate your configuration file hierarchy with visual tree structure

- **Dependency Graph** - Understand which files import which, sorted by complexity

**Navigation:**

- Use numbered menus (1, 2, 3) to select views
- Arrow keys for navigation in dependency graph
- Press `0` to go back
- Press `q` to quit

## Configuration Guide

### Adding a New Machine

The wizard makes this easy, but you can also do it manually:

**1. Run the wizard:**

```bash
nix-me setup
```

**2. Or add manually to `flake.nix`:**

```nix
darwinConfigurations = {
  "my-machine" = mkDarwinSystem {
    hostname = "my-machine";
    machineType = "macbook";       # or "macmini" or "vm"
    machineName = "My MacBook Pro";
    username = "yourusername";     # From whoami
  };
};
```

**3. Build:**

```bash
make switch
```

### Customizing Packages

#### Using the CLI (Easiest)

```bash
# Search and add apps interactively
nix-me add app docker

# Add CLI tools
nix-me add tool ripgrep

# Interactive customization menu
nix-me customize
```

#### Manual Configuration

**CLI tools** - Edit `modules/darwin/apps/installations.nix`:

```nix
systemPackages = [
  "ripgrep"
  "fd"
  "jq"        # Add your tools here
];
```

**GUI applications** - Edit the same file:

```nix
casks = [
  "visual-studio-code"
  "docker"
  "spotify"   # Add your apps here
];
```

#### Per-Machine Customization

Use the inheritance system in `hosts/[hostname]/default.nix`:

```nix
{ ... }:
{
  apps = {
    useBaseLists = true;  # Inherit from base lists

    # Remove apps you don't need
    casksToRemove = [
      "adobe-creative-cloud"
      "vmware-fusion"
    ];

    # Add machine-specific apps
    casksToAdd = [
      "amphetamine"
      "coconutbattery"
    ];

    # CLI tools via Homebrew
    brewsToAdd = ["wget" "tree"];
    brewsToRemove = ["gcc"];

    # System packages via Nix
    systemPackagesToAdd = ["htop" "ncdu"];
    systemPackagesToRemove = ["nodejs_22"];

    # Mac App Store apps
    masAppsToAdd = {
      "Bear" = 1091189122;
      "Things" = 904280696;
    };
    masAppsToRemove = ["Xcode"];
  };
}
```

**Inheritance Benefits:**

- Start with a complete base configuration
- Add/remove packages per machine
- No duplication across machines
- Easy to maintain and update

### Fish Shell Configuration

**Built-in functions:**

- `mknode <name>` - Create Node.js project with Nix environment
- `nixify` - Add Nix support to existing Node.js projects
- `mkcd <dir>` - Create and cd into directory
- `gst`, `gd`, `gcm` - Git shortcuts

**Keyboard shortcuts:**

- `Ctrl+T` - Fuzzy file search
- `Ctrl+R` - Command history search
- `Ctrl+E` - Directory navigation

**Autopair:**

- Auto-closes `()`, `[]`, `{}`, `""`, `''`
- Smart backspace removes matching pairs

Edit configuration: `modules/home-manager/fish.nix`

### SSH with 1Password

**Setup:**

1. Open 1Password 8
2. Settings → Developer → Enable "Use the SSH agent"
3. Add your SSH keys to 1Password
4. Configure keys to allow access to `github.com`

**Test:**

```bash
ssh-add -l              # List keys
ssh -T git@github.com   # Test GitHub
```

**Configuration:** `modules/home-manager/ssh.nix`

## Machine Types

### MacBook

Optimized for portability and battery life:

- Battery preservation settings
- Trackpad optimization
- Power management
- Smaller UI elements

### Mac Mini

Optimized for desktop performance:

- Multi-display support
- Performance optimization
- Professional tools
- Larger UI elements

### VM

Optimized for virtual environments:

- Minimal packages
- Reduced resource usage
- Disabled problematic features
- Fast boot

## System Management

### Daily Operations

```bash
# Apply configuration changes
make switch

# Update packages and apply
make update switch

# Check configuration validity
make check

# See all commands
make help
```

### Using nix-me

```bash
# Configuration inspector (interactive TUI)
nix-me inspect

# Diagnostics
nix-me doctor

# Current status
nix-me status

# List packages
nix-me list

# Full customization menu
nix-me customize

# VM management
nix-me vm create    # Create new test VM
nix-me vm list      # List all VMs
nix-me vm start     # Start a VM
```

## Troubleshooting

### Common Issues

**"primary username does not exist"**

Set username explicitly in your machine config in `flake.nix`:

```nix
username = "yourusername";  # Use output from whoami
```

**Nix installation broken**

Force reinstall:

```bash
FORCE_NIX_REINSTALL=1 ./install.sh
```

**1Password SSH not working**

```bash
# Check socket exists
ls -la ~/Library/Group\ Containers/2BUA8C4S2C.com.1password/t/agent.sock

# Set agent manually
export SSH_AUTH_SOCK="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
ssh-add -l
```

**Git divergence**

```bash
cd ~/.config/nixpkgs
git pull origin main
```

**Configuration errors**

```bash
# Validate config
make check

# Rollback to previous version
sudo darwin-rebuild switch --rollback
```

### Getting Help

```bash
# System diagnostics
nix-me doctor

# Check logs
darwin-rebuild switch --show-trace

# Validate configuration
make check
```

## Advanced Usage

### Command-Line Installation

For automation or CI/CD:

```bash
# With all parameters
./install.sh hostname macbook "My MacBook" yourusername

# Non-interactive mode
NON_INTERACTIVE=1 ./install.sh

# Different branch
REPO_BRANCH=refactoring ./install.sh
```

### Environment Variables

```bash
FORCE_NIX_REINSTALL=1    # Force complete Nix reinstall
NON_INTERACTIVE=1        # Skip all prompts
SKIP_BREW_ON_VM=1        # Skip Homebrew in VMs
REPO_BRANCH=branch       # Use specific git branch
```

### Modifying Existing Machines

Run the wizard to modify existing configurations:

```bash
nix-me setup
```

Select an existing machine, then choose what to modify:

- Username
- Machine type
- Machine name
- Add/remove packages

## Examples

### Photography Workstation

```nix
# hosts/photo-station/default.nix
{ ... }:
{
  apps = {
    useBaseLists = true;
    casksToRemove = ["docker" "visual-studio-code" "slack"];
    casksToAdd = [
      "adobe-lightroom"
      "capture-one"
      "pixelmator-pro"
    ];
    brewsToRemove = ["terraform" "k3d" "helm"];
    systemPackagesToRemove = ["nodejs_22" "go"];
  };
}
```

### Minimal Development Laptop

```nix
# hosts/dev-laptop/default.nix
{ ... }:
{
  apps = {
    useBaseLists = true;
    casksToRemove = ["adobe-creative-cloud" "obs" "spotify"];
    casksToAdd = ["postman" "dash"];
    brewsToAdd = ["httpie" "wget"];
    systemPackagesToAdd = ["jq" "yq"];
  };

  system.defaults.dock.tilesize = 32;
}
```

### Work Profile with Extra Tools

```nix
# hosts/work-laptop/default.nix
{ ... }:
{
  imports = [
    ../profiles/work.nix  # Import work profile
  ];

  apps = {
    useBaseLists = true;
    casksToAdd = [
      "microsoft-teams"
      "slack"
      "zoom"
    ];
    brewsToAdd = [
      "kubectl"
      "helm"
      "terraform"
    ];
  };
}
```

## Updating

### Update Packages

```bash
# Via nix-me
nix-me update

# Or manually
make update switch
```

### Update Configuration

```bash
cd ~/.config/nixpkgs
git pull
make switch
```

## Uninstalling

### Remove nix-darwin

```bash
sudo /nix/var/nix/profiles/system/sw/bin/darwin-uninstaller
```

### Complete Nix Removal

```bash
sudo /nix/uninstall
rm -rf ~/.config/nixpkgs
```

## FAQ

**Do I need to know Nix?**

No! The interactive wizard and `nix-me` CLI tool handle everything. You can customize your system without touching Nix code.

**Will this break my existing setup?**

No. The installer:

- Backs up existing configurations
- Preserves manually installed apps
- Can be completely removed
- Supports rollbacks

**How much disk space does this use?**

~1-5GB for the Nix store (shared between all packages).

**Can I use this on my work machine?**

Yes, with considerations:

- Requires admin privileges for setup
- Check company policies on package managers
- All packages from official repositories

**How do I backup my configuration?**

Your entire configuration is in git:

```bash
cd ~/.config/nixpkgs
git add .
git commit -m "My customizations"
git push
```

Restore anywhere:

```bash
git clone your-fork.git ~/.config/nixpkgs
cd ~/.config/nixpkgs
./install.sh
```

**Performance impact?**

- Minimal runtime overhead
- No additional RAM usage during normal operation
- Network only during updates

**Supported macOS versions?**

- macOS 10.15 Catalina and later
- Intel and Apple Silicon
- VMs (UTM, VMware, Parallels)

## Contributing

Contributions welcome!

1. Fork the repository
2. Create a feature branch
3. Test with `make build`
4. Submit a pull request

## License

MIT License

## Acknowledgments

Inspired by:

- [Mitchell Hashimoto's nixos-config](https://github.com/mitchellh/nixos-config)
- [nix-darwin](https://github.com/LnL7/nix-darwin)
- [Home Manager](https://github.com/nix-community/home-manager)

---

**Need help?** Run `nix-me doctor` for diagnostics or check the [troubleshooting section](#troubleshooting).

**Want to customize?** Run `nix-me customize` for an interactive menu.
