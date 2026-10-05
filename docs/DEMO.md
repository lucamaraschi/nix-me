# nix-me Interactive Demo

This document demonstrates the new interactive CLI features.

## 🎉 What's New

### 1. Interactive Configuration Wizard

Beautiful, guided setup experience:

```bash
$ nix-me create

🎉 nix-me Configuration Wizard

Let's set up your macOS configuration!

[1/6] Basic Information

Hostname [nabucodonosor]: work-macbook-pro
Username [batman]: batman
Display Name [work-macbook-pro]: Work MacBook Pro

[2/6] Machine Type

Machine types provide hardware-specific optimizations

  1) macbook - General MacBook (Air/Pro)
  2) macbook-pro - MacBook Pro with Pro optimizations  ← Nice!
  3) macmini - Mac Mini desktop
  4) vm - Virtual Machine

Select type [1-4]: 2
✓ Selected type: macbook-pro

[3/6] Configuration Profile

Profiles customize your system for specific use cases

  1) work - Work environment (Teams, Slack, Office, Docker, Dev tools)
  2) personal - Personal setup (Spotify, Creative apps, Entertainment)
  3) minimal - Clean slate - choose your own apps
  4) custom - Create a custom profile

Select profile [1-4]: 1
✓ Selected profile: work

[4/6] Application Selection

Your profile includes default apps. Add more if needed.

How would you like to select apps?

  1) Browse all apps with search
  2) Browse by category
  3) Search for specific apps
  4) Skip - use profile defaults

Choice [4]: 1
```

### 2. fzf-Powered Package Browser

Beautiful interactive browser with live previews:

```
┌─────────────────────────────────────────────────────────────────────┐
│ Select apps > doc                                            5/342   │
├─────────────────────────────────────────────────────────────────────┤
│ > docker                                                             │
│   docker-desktop                                                     │
│   dockerfile-language-server                                         │
│   visual-studio-code                                                 │
│   postman                                                            │
└─────────────────────────────────────────────────────────────────────┘
  TAB: select multiple | ENTER: confirm | ESC: cancel | Ctrl+A: all

┌─ Preview ───────────────────────────────────────────────────────────┐
│ docker-desktop                                                       │
│                                                                      │
│ Docker Desktop                                                       │
│ Pack, ship and run any application as a lightweight container       │
│                                                                      │
│ ==> Caveats                                                          │
│ You must log in to Docker Desktop to use Docker Desktop.            │
│                                                                      │
│ ==> Analytics                                                        │
│ https://docs.docker.com/desktop/                                    │
└──────────────────────────────────────────────────────────────────────┘
```

### 3. Category Browsing

Browse apps organized by category:

```bash
$ nix-me browse

Browse Applications

  1) Browse all applications
  2) Browse by category              ← New!
  3) Search specific apps

Choice [1]: 2

┌─────────────────────────────────────────────────────────────────────┐
│ Select category >                                             9/9    │
├─────────────────────────────────────────────────────────────────────┤
│   Development                                                        │
│ > Design                                                             │
│   Productivity                                                       │
│   Communication                                                      │
│   Browsers                                                           │
│   Media                                                              │
│   Utilities                                                          │
│   Security                                                           │
│   Databases                                                          │
└─────────────────────────────────────────────────────────────────────┘

Figma, Sketch, Adobe Creative Cloud
```

### 4. Enhanced Search

```bash
$ nix-me search docker

Searching for applications...

┌─────────────────────────────────────────────────────────────────────┐
│ Select apps > docker                                         12/342  │
├─────────────────────────────────────────────────────────────────────┤
│ > docker                                                             │
│   docker-desktop                                                     │
│   orbstack                                                           │
└─────────────────────────────────────────────────────────────────────┘

Selected 1 apps:
  • docker-desktop

Add these to your configuration? (Y/n): y

Adding Applications to Configuration
Target machine: work-macbook-pro

Where should these apps be added?

  1) Host-specific config (nix/hosts/machines/work-macbook-pro/default.nix)
  2) Base configuration (nix/modules/darwin/apps/installations.nix)

Choice [1]: 1

Apps to add:
  • docker-desktop

Add these apps to nix/hosts/machines/work-macbook-pro/default.nix? (Y/n): y
✓ Configuration updated!

Apply changes now? (Y/n): y

Applying Configuration
Building and applying configuration...
✓ Configuration applied successfully!
```

### 5. Smart App Addition

Multiple ways to add apps:

```bash
# Interactive browsing
$ nix-me browse

# Direct search
$ nix-me search spotify

# Quick add (searches automatically)
$ nix-me add app docker

# Add CLI tools
$ nix-me add tool ripgrep
```

### 6. Reconfigure Existing Machines

```bash
$ nix-me reconfigure work-macbook-pro

Reconfigure Machine: work-macbook-pro

What would you like to modify?

  1) Add applications
  2) Change profile
  3) Edit configuration file
  0) Cancel

Choice: 1

(Opens interactive browser...)
```

### 7. Enhanced Diagnostics

```bash
$ nix-me doctor

System Diagnostics

[1/8] Checking Nix installation
✓ Nix is installed: nix (Nix) 2.19.2

[2/8] Checking nix-darwin
✓ nix-darwin is installed

[3/8] Validating configuration
✓ Configuration directory exists
✓ Configuration is valid

[4/8] Checking Homebrew
✓ Homebrew is installed

[5/8] Checking interactive tools
✓ fzf is installed (interactive features available)

[6/8] Checking 1Password SSH agent
✓ 1Password SSH agent is available
  Keys available: 3

[7/8] Checking disk space
  Available space: 145Gi (32% used)
  Nix store size: 12G

[8/8] Common issues
✓ No issues detected

Diagnostics Complete

✅ Your system is healthy!
```

## Command Comparison

### Before (Manual)

```bash
# Had to manually edit files
vim ~/.config/nixpkgs/nix/modules/darwin/apps/installations.nix
# Find the casks array
# Add "docker"
# Save

# Then apply
cd ~/.config/nixpkgs
make switch
```

### After (Interactive)

```bash
# One command
nix-me browse
# Select apps with nice UI
# Automatically applied
```

## Real-World Usage Examples

### Example 1: New Developer Machine

```bash
# Create configuration
$ nix-me create
> work-macbook-pro
> macbook-pro
> work profile

# Configuration includes: VSCode, Docker, Slack, Teams, Office
# ✓ Auto-applied

# Add project-specific tools
$ nix-me browse
> Select: TablePlus, Postman, Insomnia

$ nix-me switch
✓ Done! Ready to code.
```

### Example 2: Personal Creative Workstation

```bash
$ nix-me create
> creative-studio
> macmini
> personal profile

# Browse by category
$ nix-me browse
> Choose: Browse by category
> Design → Select: Figma, Adobe CC, Sketch

$ nix-me browse
> Choose: Browse by category
> Media → Select: OBS, Logic Pro, DaVinci Resolve

$ nix-me switch
✓ Creative workstation ready!
```

### Example 3: Minimal Setup

```bash
$ nix-me create
> minimal-mac
> macbook
> minimal profile

# Only add what you need
$ nix-me search browser
> Select: Arc

$ nix-me search code
> Select: Cursor

$ nix-me switch
✓ Clean, minimal setup!
```

## Interactive Features Showcase

### Multi-Select Workflow

```
1. nix-me browse
2. TAB on docker ✓
3. TAB on visual-studio-code ✓
4. TAB on postman ✓
5. TAB on tableplus ✓
6. ENTER
   → Adds all 4 at once!
```

### Keyboard Shortcuts

```bash
# In browse mode:
Ctrl+A    # Select all in current view
Ctrl+D    # Deselect all
TAB       # Toggle selection
↑↓        # Navigate
/         # Start typing to filter
ENTER     # Confirm
ESC       # Cancel
```

### Search with Preview

```
Type: "vs code"
↓ Visual Studio Code appears
→ Preview shows: "Code editor by Microsoft..."
TAB to select
ENTER to add
```

## Architecture

### New Library Structure

```
lib/
├── ui.sh                # Terminal UI helpers
├── config-builder.sh    # Configuration generation
├── wizard.sh            # Original simple wizard
├── config-wizard.sh     # NEW: Enhanced wizard with profiles
└── package-manager.sh   # NEW: Interactive package browsing
```

### Integration Flow

```
nix-me browse
    ↓
package-manager.sh (browse_homebrew_casks_fzf)
    ↓
fzf interactive interface
    ↓
User selects apps (TAB)
    ↓
add_casks_to_config
    ↓
Updates nix/hosts/machines/<hostname>/default.nix
    ↓
Optionally applies with switch
```

## Benefits

### For Users

✅ **No Nix knowledge required** - Wizard handles everything
✅ **Beautiful UI** - fzf provides smooth experience
✅ **Fast package discovery** - Browse 300+ apps easily
✅ **Multi-select** - Add many apps at once
✅ **Live previews** - See app descriptions before selecting
✅ **Category browsing** - Find apps by purpose
✅ **Instant feedback** - Apply and see results immediately

### For Developers

✅ **Modular design** - Easy to extend
✅ **Profile system** - Reusable configurations
✅ **Automated config generation** - No manual file editing
✅ **Error handling** - Graceful fallbacks
✅ **Git integration** - Safe configuration changes
✅ **Diagnostic tools** - Easy troubleshooting

## Installation

After install, the enhanced CLI is immediately available:

```bash
# Fresh install
curl -L https://raw.githubusercontent.com/.../install.sh | bash

# nix-me command is now available with all features
nix-me --help
```

## Compatibility

- ✅ Works with existing configurations
- ✅ Backward compatible with old wizard
- ✅ Graceful fallback if fzf not installed
- ✅ Homebrew and Nix package support
- ✅ All machine types (macbook, macmini, vm)
- ✅ All profiles (work, personal, minimal)

## Try It Out

```bash
# 1. Create new config
nix-me create

# 2. Browse and add apps
nix-me browse

# 3. Search for specific apps
nix-me search docker

# 4. Check status
nix-me status

# 5. Run diagnostics
nix-me doctor
```

---

**Full documentation:**
- [CLI_GUIDE.md](docs/CLI_GUIDE.md) - Complete CLI reference
- [QUICK_REFERENCE.md](docs/QUICK_REFERENCE.md) - Quick command reference
- [CUSTOMIZATION.md](CUSTOMIZATION.md) - Advanced customization
- [PROFILES.md](docs/PROFILES.md) - Profile system guide
