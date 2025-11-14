# nix-me CLI Guide

Complete guide to using the nix-me command-line interface.

## Table of Contents

- [Quick Start](#quick-start)
- [Configuration Commands](#configuration-commands)
- [Package Management](#package-management)
- [System Management](#system-management)
- [Information Commands](#information-commands)
- [Interactive Features](#interactive-features)
- [Examples](#examples)

## Quick Start

```bash
# First time setup
nix-me create

# Browse and add apps
nix-me browse

# Apply changes
nix-me switch

# Check system health
nix-me doctor
```

## Configuration Commands

### `nix-me create` (or `nix-me setup`)

Launch the interactive configuration wizard to create a new machine configuration.

**Features:**
- Step-by-step guided setup
- Machine type selection (macbook, macbook-pro, macmini, vm)
- Profile selection (work, personal, minimal, custom)
- Interactive package selection with fzf
- Category browsing
- Automatic configuration generation

**Example:**
```bash
nix-me create

# Wizard will guide you through:
# 1. Basic info (hostname, username, display name)
# 2. Machine type selection
# 3. Profile selection
# 4. Application selection
# 5. Configuration summary
# 6. Generation and setup
```

### `nix-me reconfigure [hostname]`

Modify an existing machine configuration.

**Options:**
1. Add applications
2. Change profile
3. Edit configuration file

**Example:**
```bash
# Reconfigure current machine
nix-me reconfigure

# Reconfigure specific machine
nix-me reconfigure work-macbook
```

## Package Management

### `nix-me browse`

Interactive application browser with beautiful UI.

**Features:**
- **fzf-powered interface** with fuzzy search
- **Live preview** showing app descriptions
- **Multi-select** (TAB to select, ENTER to confirm)
- **Category browsing** (Development, Design, Media, etc.)
- **Search filtering**

**Keyboard shortcuts in browse mode:**
- `↑/↓` - Navigate
- `TAB` - Select/deselect
- `Ctrl+A` - Select all
- `Ctrl+D` - Deselect all
- `ENTER` - Confirm selection
- `ESC` - Cancel

**Example:**
```bash
nix-me browse

# Then choose:
# 1) Browse all applications
# 2) Browse by category
# 3) Search specific apps
```

### `nix-me search <query>`

Search for applications matching a query.

**Example:**
```bash
# Search for Docker
nix-me search docker

# Search for design apps
nix-me search figma

# Search for browsers
nix-me search chrome
```

**Output:**
- Opens interactive browser with search results
- Select multiple apps with TAB
- Add to configuration

### `nix-me add app [name]`

Add GUI application(s).

**Without arguments:** Opens interactive browser
**With name:** Searches for specific app

**Example:**
```bash
# Interactive mode
nix-me add app

# Search and add specific app
nix-me add app spotify
nix-me add app docker
```

### `nix-me add tool <name>`

Add CLI tool via Nix.

**Example:**
```bash
nix-me add tool ripgrep
nix-me add tool jq
nix-me add tool kubectl
```

### `nix-me remove`

Remove packages (interactive - coming soon).

## System Management

### `nix-me switch`

Build and apply configuration changes.

**What it does:**
1. Validates configuration
2. Builds Nix derivations
3. Installs Homebrew casks
4. Applies system settings
5. Activates new generation

**Example:**
```bash
nix-me switch
```

**When to use:**
- After adding/removing packages
- After editing configuration files
- After profile changes
- To apply system setting changes

### `nix-me build`

Build configuration without applying (test mode).

**Use this to:**
- Test configuration changes
- Catch errors before applying
- Verify Nix expressions

**Example:**
```bash
# Make changes to config
vim ~/.config/nixpkgs/hosts/myhost/default.nix

# Test the build
nix-me build

# If successful, apply
nix-me switch
```

### `nix-me update`

Update all packages to latest versions.

**What it updates:**
- Nix flake inputs
- nixpkgs version
- All Nix packages
- Homebrew casks (via switch)

**Example:**
```bash
nix-me update

# It will ask if you want to apply immediately
```

### `nix-me rollback`

Rollback to previous system generation.

**Use when:**
- New configuration has issues
- Package update breaks something
- Need to revert changes quickly

**Example:**
```bash
nix-me rollback

# Shows recent generations and confirms rollback
```

## Information Commands

### `nix-me status`

Show comprehensive system status.

**Displays:**
- Configuration location and git branch
- Current machine/hostname
- Active Nix generation
- Package counts (Homebrew + Nix)
- Disk usage

**Example:**
```bash
nix-me status
```

### `nix-me doctor`

Run system diagnostics and health checks.

**Checks:**
1. Nix installation and version
2. nix-darwin availability
3. Configuration validity
4. Homebrew status
5. Interactive tools (fzf)
6. 1Password SSH agent
7. Disk space
8. Common issues

**Example:**
```bash
nix-me doctor

# Diagnoses and suggests fixes
```

### `nix-me list`

List all installed packages.

**Shows:**
- Homebrew casks (GUI apps)
- Nix packages (CLI tools)
- Package counts

**Example:**
```bash
nix-me list

# Tip: Pipe to grep for filtering
nix-me list | grep docker
```

### `nix-me diff`

Show uncommitted configuration changes.

**Displays:**
- Git diff of config files
- Recent commits
- Changed files

**Example:**
```bash
nix-me diff
```

## Interactive Features

### fzf Integration

When `fzf` is installed, nix-me provides enhanced interactive features:

**In browse mode:**
```
┌─ Select apps ───────────────────────────────────┐
│ > docker                                         │
│   visual-studio-code                             │
│   spotify                                        │
│   slack                                          │
│   zoom                                           │
└──────────────────────────────────────────────────┘
TAB: select multiple | ENTER: confirm | ESC: cancel

┌─ Preview ────────────────────────────────────────┐
│ docker                                           │
│                                                  │
│ Docker Desktop: container platform               │
│ Version: 4.x.x                                   │
│ Size: ~500MB                                     │
└──────────────────────────────────────────────────┘
```

**Install fzf:**
```bash
nix-me add tool fzf
nix-me switch
```

### Category Browsing

Browse applications by category:

**Available categories:**
- **Development** - IDEs, Git clients, Docker, etc.
- **Productivity** - Notion, Todoist, Calendar apps
- **Communication** - Slack, Discord, Zoom, Teams
- **Design** - Figma, Sketch, Adobe Creative Cloud
- **Browsers** - Chrome, Firefox, Brave, Arc
- **Media** - Spotify, VLC, OBS, Handbrake
- **Utilities** - Rectangle, Raycast, Alfred
- **Security** - 1Password, VPN clients, Little Snitch
- **Databases** - TablePlus, Sequel Ace, DBeaver

**Access via:**
```bash
nix-me browse
# Choose option 2: Browse by category
```

## Examples

### Complete Workflow: New Machine Setup

```bash
# 1. Create configuration
nix-me create

# Follow wizard:
#   - Hostname: work-macbook-pro
#   - Type: macbook-pro
#   - Profile: work
#   - Select additional apps

# 2. Configuration is generated
# Location: ~/.config/nixpkgs/hosts/work-macbook-pro

# 3. Build and apply
nix-me switch

# 4. Verify
nix-me status
nix-me doctor
```

### Adding Apps After Setup

```bash
# Interactive browsing
nix-me browse

# Or search directly
nix-me search spotify
nix-me search docker
nix-me search figma

# Apply changes
nix-me switch
```

### Switching from Work to Personal Profile

```bash
# 1. Edit your machine configuration
vim ~/.config/nixpkgs/flake.nix

# 2. Change extraModules:
#    FROM: ./hosts/profiles/work.nix
#    TO:   ./hosts/profiles/personal.nix

# 3. Apply
nix-me switch
```

### Maintaining Your System

```bash
# Weekly: Update packages
nix-me update
nix-me switch

# As needed: Add/remove apps
nix-me browse
nix-me switch

# Check health
nix-me doctor

# View what's installed
nix-me list
```

### Troubleshooting

```bash
# 1. Check system health
nix-me doctor

# 2. View configuration changes
nix-me diff

# 3. Test build before applying
nix-me build

# 4. If something breaks, rollback
nix-me rollback

# 5. Check recent status
nix-me status
```

### Advanced: Multi-Machine Management

```bash
# Create work machine
nix-me create
# Choose: work-macbook-pro, type: macbook-pro, profile: work

# Create personal machine
nix-me create
# Choose: personal-mac, type: macbook, profile: personal

# Switch between machines
cd ~/.config/nixpkgs
make switch HOST=work-macbook-pro
make switch HOST=personal-mac
```

## Tips and Tricks

### 1. Use Tab Completion

If you have fish shell configured:
```fish
nix-me <TAB>  # Shows available commands
```

### 2. Combine Commands

```bash
# Add multiple apps in one session
nix-me browse
# Select multiple with TAB, then apply all at once
```

### 3. Test Before Applying

```bash
# Safe workflow
nix-me build   # Test first
nix-me switch  # Apply if successful
```

### 4. Quick Health Check

```bash
# Before making changes
nix-me doctor
nix-me status
```

### 5. Backup Before Major Changes

```bash
cd ~/.config/nixpkgs
git commit -am "Backup before major changes"
```

### 6. Find Package Names

For Homebrew casks:
```bash
brew search docker
nix-me search docker
```

For Nix packages:
```bash
nix search nixpkgs ripgrep
```

## Configuration File Locations

```
~/.config/nixpkgs/
├── flake.nix                          # Machine definitions
├── hosts/
│   ├── <hostname>/
│   │   └── default.nix                # Your machine config
│   ├── profiles/
│   │   ├── work.nix                   # Work profile
│   │   └── personal.nix               # Personal profile
│   └── macbook-pro/default.nix        # Machine type defaults
└── modules/
    └── darwin/
        └── apps/
            └── installations.nix       # Base app list
```

## Environment Variables

```bash
# Override default editor
export EDITOR=vim
export EDITOR=code

# Default config location
export CONFIG_DIR="$HOME/.config/nixpkgs"
```

## Getting Help

```bash
# General help
nix-me help
nix-me --help

# Command-specific help
nix-me <command> --help

# System diagnostics
nix-me doctor

# Check status
nix-me status
```

## See Also

- [README.md](../README.md) - Project overview
- [CUSTOMIZATION.md](../CUSTOMIZATION.md) - Advanced customization
- [PROFILES.md](./PROFILES.md) - Profile system guide
- [GitHub Issues](https://github.com/lucamaraschi/nix-me/issues) - Report bugs

---

**Pro Tip:** Start with `nix-me create` to get a working configuration, then refine with `nix-me browse` and `nix-me reconfigure`.
