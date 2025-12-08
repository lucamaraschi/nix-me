<p align="center">
  <img src="https://nixos.org/logo/nixos-hires.png" width="120" alt="Nix Logo">
</p>

<h1 align="center">nix-me</h1>

<p align="center">
  <strong>Declarative macOS configuration made simple</strong>
</p>

<p align="center">
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT"></a>
  <a href="https://nixos.org"><img src="https://img.shields.io/badge/Built%20with-Nix-5277C3.svg?logo=nixos&logoColor=white" alt="Built with Nix"></a>
  <a href="https://www.apple.com/macos/"><img src="https://img.shields.io/badge/macOS-Sequoia+-000000?logo=apple&logoColor=white" alt="macOS"></a>
  <a href="https://github.com/lucamaraschi/nix-me/stargazers"><img src="https://img.shields.io/github/stars/lucamaraschi/nix-me?style=social" alt="Stars"></a>
</p>

<p align="center">
  <em>Manage your entire Mac development environment as code.<br>No Nix knowledge required.</em>
</p>

---

## Overview

**nix-me** transforms macOS system configuration into a reproducible, version-controlled experience. Whether you're setting up a new machine or keeping multiple Macs in sync, nix-me makes it effortless.

<table>
<tr>
<td width="50%">

### What You Get

- **Interactive Setup Wizard** - Clone from existing hosts or start fresh
- **Composable Profiles** - Mix dev, work, and personal configs
- **Powerful CLI** - `nix-me` command for all operations
- **Multi-Machine Support** - MacBooks, Mac Minis, VMs
- **Reproducible Builds** - Same config = same result
- **Rollback Safety** - Undo any change instantly

</td>
<td width="50%">

### How It Works

```
┌─────────────────────────────────────┐
│  Profiles (composable)              │
│  dev + work + personal              │
└─────────────┬───────────────────────┘
              │
              ▼
┌─────────────────────────────────────┐
│  Machine Type                       │
│  macbook / macmini / vm             │
└─────────────┬───────────────────────┘
              │
              ▼
┌─────────────────────────────────────┐
│  Nix Packages │ Homebrew │ App Store│
└─────────────────────────────────────┘
```

</td>
</tr>
</table>

---

## Quick Start

### One-Line Install

```bash
curl -L https://raw.githubusercontent.com/lucamaraschi/nix-me/main/install.sh | bash
```

The wizard will guide you through:
1. **Clone or create** - Copy settings from an existing host or start fresh
2. **Select profiles** - Choose dev, work, personal (or combine them)
3. **Configure machine** - Set hostname, type, and username
4. **Build system** - Apply your configuration

> **Time:** 30-60 minutes (mostly package downloads)

### Prerequisites

| Requirement | Details |
|-------------|---------|
| macOS | 10.15 Catalina or later |
| Architecture | Intel or Apple Silicon |
| Disk Space | ~5GB free |
| Privileges | Admin access required |

---

## Profiles

Profiles are **composable** - combine them to match your needs:

<table>
<tr>
<th>Profile</th>
<th>What's Included</th>
<th>Use Case</th>
</tr>
<tr>
<td><code>dev</code></td>
<td>

- VS Code, Ghostty, Docker
- Node.js, Python, Go, Rust
- GitHub CLI, Xcode
- k3d, OrbStack, UTM

</td>
<td>Software development</td>
</tr>
<tr>
<td><code>work</code></td>
<td>

- Slack, Teams, Zoom
- Notion, Linear, Miro
- Microsoft Office, Figma
- Terraform, kubectl, AWS CLI

</td>
<td>Work collaboration</td>
</tr>
<tr>
<td><code>personal</code></td>
<td>

- Spotify, OBS
- yt-dlp, ffmpeg
- iA Writer, PDF Expert

</td>
<td>Entertainment & personal</td>
</tr>
</table>

### Profile Combinations

```nix
# Work developer (most common)
extraModules = [
  ./hosts/profiles/dev.nix
  ./hosts/profiles/work.nix
];

# Personal dev machine
extraModules = [
  ./hosts/profiles/dev.nix
  ./hosts/profiles/personal.nix
];

# Full setup (everything)
extraModules = [
  ./hosts/profiles/dev.nix
  ./hosts/profiles/work.nix
  ./hosts/profiles/personal.nix
];

# Minimal (no profiles - just base essentials)
# Simply omit extraModules
```

---

## The `nix-me` CLI

After installation, manage your system with the `nix-me` command:

### Essential Commands

```bash
nix-me status          # System overview
nix-me switch          # Apply configuration changes
nix-me update          # Update all packages
nix-me diff            # Preview changes before applying
```

### Package Management

```bash
nix-me add app slack   # Add a GUI application
nix-me add tool jq     # Add a CLI tool
nix-me list            # View installed packages
nix-me browse          # Interactive package browser
```

### Configuration

```bash
nix-me setup           # Run setup wizard (with clone support)
nix-me customize       # Interactive customization menu
nix-me inspect         # TUI configuration explorer
nix-me doctor          # Diagnose issues
```

---

## Architecture

```
nix-me/
├── flake.nix                 # Machine definitions & inputs
├── install.sh                # Interactive installer
│
├── bin/
│   └── nix-me                # CLI tool
│
├── hosts/
│   ├── types/
│   │   ├── shared/           # Common settings (all machines)
│   │   ├── macbook/          # MacBook optimizations
│   │   ├── macbook-pro/      # MacBook Pro optimizations
│   │   ├── macmini/          # Mac Mini optimizations
│   │   └── vm/               # VM optimizations
│   │
│   ├── profiles/             # Composable profiles
│   │   ├── dev.nix           # Development tools
│   │   ├── work.nix          # Work/collaboration apps
│   │   └── personal.nix      # Entertainment/personal
│   │
│   └── machines/
│       └── [hostname]/       # Machine-specific overrides
│
├── modules/
│   ├── darwin/               # System-level (nix-darwin)
│   │   ├── apps/
│   │   │   └── installations.nix  # Base package lists
│   │   ├── core.nix
│   │   ├── system.nix
│   │   └── ...
│   │
│   └── home-manager/         # User-level (home-manager)
│       ├── shell/
│       │   └── fish.nix
│       ├── git.nix
│       ├── ssh.nix
│       └── ...
│
├── lib/                      # Shell libraries
│   ├── ui.sh
│   ├── wizard.sh             # Setup wizard with clone support
│   ├── config-builder.sh     # Config generation
│   └── ...
│
└── tui/                      # React TUI (Configuration Inspector)
    └── src/
```

---

## Machine Types

<table>
<tr>
<th>MacBook</th>
<th>Mac Mini</th>
<th>VM</th>
</tr>
<tr>
<td>

Optimized for mobility:
- Battery preservation
- Trackpad gestures
- Smaller dock icons
- Power management

</td>
<td>

Optimized for desktop:
- Multi-display support
- Larger UI elements
- Performance mode
- Professional tools

</td>
<td>

Optimized for testing:
- Minimal packages
- Reduced resources
- Fast boot times
- No App Store apps

</td>
</tr>
</table>

---

## Configuration

### Adding a Machine

**Option 1: Clone from Existing Host**

```bash
nix-me setup
# Choose: [2] Clone settings from an existing host
# Select the source host
# The wizard copies machine type and profiles
```

**Option 2: Interactive Wizard**
```bash
nix-me setup
# Choose: [1] Create new configuration from scratch
# Select machine type, profiles, etc.
```

**Option 3: Manual Configuration**

Add to `flake.nix`:
```nix
"my-machine" = mkDarwinSystem {
  hostname = "my-machine";
  machineType = "macbook";     # or "macbook-pro", "macmini", "vm"
  machineName = "My MacBook";
  username = "yourusername";
  extraModules = [
    ./hosts/profiles/dev.nix   # Development tools
    ./hosts/profiles/work.nix  # Work apps
  ];
};
```

### Customizing Packages

**Per-machine customization** in `hosts/machines/[hostname]/default.nix`:

```nix
{ ... }:
{
  apps = {
    useBaseLists = true;           # Inherit base packages

    # GUI apps (Homebrew Casks)
    casksToAdd = [ "figma" "notion" ];
    casksToRemove = [ "spotify" ];

    # CLI tools (Homebrew)
    brewsToAdd = [ "wget" ];

    # CLI tools (Nix)
    systemPackagesToAdd = [ "jq" ];

    # Mac App Store apps
    masAppsToAdd = {
      "Keynote" = 409183694;
      "Bear" = 1091189122;
    };
    masAppsToRemove = [ "Xcode" ];
  };
}
```

### Display Configuration

Display auto-configuration is opt-in. To enable:

```nix
display.autoConfigureResolution = true;
```

This sets all displays to maximum resolution ("More Space") using `displayplacer`.

---

## Fish Shell

nix-me configures Fish shell with powerful defaults:

### Custom Functions

| Function | Description |
|----------|-------------|
| `mknode <name>` | Create Node.js project with Nix environment |
| `nixify` | Add Nix support to existing project |
| `mkcd <dir>` | Create directory and cd into it |
| `gst`, `gd`, `gcm` | Git shortcuts |

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Ctrl+T` | Fuzzy file search |
| `Ctrl+R` | Command history |
| `Ctrl+E` | Directory navigation |

### Auto-Pair

Automatically closes brackets and quotes: `()` `[]` `{}` `""` `''`

---

## 1Password SSH Integration

nix-me configures SSH to use 1Password as your SSH agent.

### Setup

1. Open **1Password 8** → Settings → Developer
2. Enable **"Use the SSH agent"**
3. Add SSH keys to 1Password
4. Configure keys for `github.com` access

### Verify

```bash
ssh-add -l              # List available keys
ssh -T git@github.com   # Test GitHub connection
```

---

## Troubleshooting

<details>
<summary><strong>"primary username does not exist"</strong></summary>

Set username explicitly in `flake.nix`:
```nix
username = "yourusername";  # Output of: whoami
```
</details>

<details>
<summary><strong>Nix installation issues</strong></summary>

Force reinstall:
```bash
FORCE_NIX_REINSTALL=1 ./install.sh
```
</details>

<details>
<summary><strong>1Password SSH not working</strong></summary>

Check the socket exists:
```bash
ls -la ~/Library/Group\ Containers/2BUA8C4S2C.com.1password/t/agent.sock
```

Set manually if needed:
```bash
export SSH_AUTH_SOCK="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
```
</details>

<details>
<summary><strong>Configuration errors</strong></summary>

```bash
make check                              # Validate config
darwin-rebuild switch --show-trace      # Detailed errors
sudo darwin-rebuild switch --rollback   # Rollback changes
```
</details>

### Diagnostics

```bash
nix-me doctor    # Run full diagnostics
nix-me status    # Quick system overview
```

---

## FAQ

<details>
<summary><strong>Do I need to know Nix?</strong></summary>

No! The wizard and CLI handle everything. You can customize without touching Nix code.
</details>

<details>
<summary><strong>Will this break my existing setup?</strong></summary>

No. The installer backs up configurations, preserves existing apps, supports rollbacks, and can be completely removed.
</details>

<details>
<summary><strong>How much disk space?</strong></summary>

~1-5GB for the Nix store, shared between all packages.
</details>

<details>
<summary><strong>Can I use this at work?</strong></summary>

Yes, but check company policies. Requires admin privileges; all packages come from official repositories.
</details>

<details>
<summary><strong>How do I backup my config?</strong></summary>

It's all in git:
```bash
cd ~/.config/nixpkgs
git add . && git commit -m "My customizations" && git push
```
</details>

<details>
<summary><strong>Can I have multiple profiles on one machine?</strong></summary>

Yes! Profiles are composable. Combine dev + work, dev + personal, or all three:
```nix
extraModules = [
  ./hosts/profiles/dev.nix
  ./hosts/profiles/work.nix
  ./hosts/profiles/personal.nix
];
```
</details>

<details>
<summary><strong>Can I clone settings from another machine?</strong></summary>

Yes! Run `nix-me setup` and choose "Clone settings from an existing host". The wizard will copy the machine type and profiles from your selected source host.
</details>

---

## Advanced Usage

### Non-Interactive Installation

```bash
# Full automation
NON_INTERACTIVE=1 ./install.sh hostname macbook "My Mac" username

# Environment variables
FORCE_NIX_REINSTALL=1    # Force Nix reinstall
SKIP_BREW_ON_VM=1        # Skip Homebrew in VMs
REPO_BRANCH=dev          # Use specific branch
```

### Make Commands

```bash
make switch    # Apply configuration
make update    # Update flake inputs
make check     # Validate configuration
make build     # Build without applying
make help      # Show all commands
```

---

## Contributing

Contributions welcome!

1. Fork the repository
2. Create a feature branch
3. Test with `make check && make build`
4. Submit a pull request

---

## Acknowledgments

Built on the shoulders of giants:

- [nix-darwin](https://github.com/LnL7/nix-darwin) - macOS system management
- [Home Manager](https://github.com/nix-community/home-manager) - User environment management
- [Mitchell Hashimoto's config](https://github.com/mitchellh/nixos-config) - Inspiration

---

<p align="center">
  <strong>Need help?</strong> Run <code>nix-me doctor</code><br>
  <strong>Want to customize?</strong> Run <code>nix-me customize</code>
</p>

<p align="center">
  <sub>MIT License • Made with Nix</sub>
</p>
