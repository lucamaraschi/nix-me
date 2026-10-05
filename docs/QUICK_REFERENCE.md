# nix-me Quick Reference

## Essential Commands

### First Time Setup
```bash
nix-me create         # Interactive configuration wizard
```

### Daily Operations
```bash
nix-me browse         # Browse and add apps (interactive)
nix-me search docker  # Search for specific app
nix-me switch         # Apply configuration changes
```

### System Management
```bash
nix-me status         # Show system status
nix-me doctor         # Health check
nix-me update         # Update packages
nix-me rollback       # Undo last change
```

## Command Reference

| Command | Description | Example |
|---------|-------------|---------|
| **Configuration** | | |
| `create` | New machine wizard | `nix-me create` |
| `reconfigure` | Modify existing config | `nix-me reconfigure` |
| **Packages** | | |
| `browse` | Interactive app browser | `nix-me browse` |
| `search <query>` | Search for apps | `nix-me search spotify` |
| `add app <name>` | Add GUI app | `nix-me add app docker` |
| `add tool <name>` | Add CLI tool | `nix-me add tool ripgrep` |
| **System** | | |
| `switch` | Apply changes | `nix-me switch` |
| `build` | Test build | `nix-me build` |
| `update` | Update all | `nix-me update` |
| `rollback` | Revert changes | `nix-me rollback` |
| **Info** | | |
| `status` | System status | `nix-me status` |
| `doctor` | Diagnostics | `nix-me doctor` |
| `list` | List packages | `nix-me list` |
| `diff` | Show changes | `nix-me diff` |

## Interactive Browser Keys

When using `nix-me browse`:

```
↑ ↓         Navigate
TAB         Select/deselect
Ctrl+A      Select all
Ctrl+D      Deselect all
ENTER       Confirm
ESC         Cancel
```

## Common Workflows

### New Machine
```bash
1. nix-me create          # Wizard setup
2. Select options         # Follow prompts
3. Browse & add apps      # Optional
4. Automatically applied  # Or run: nix-me switch
```

### Add Apps
```bash
# Interactive
nix-me browse

# Or search
nix-me search <app-name>

# Apply
nix-me switch
```

### Update System
```bash
nix-me update    # Updates packages
nix-me switch    # Applies updates
```

### Fix Issues
```bash
nix-me doctor     # Diagnose
nix-me rollback   # Revert if needed
```

## Profile Types

- **work** - Productivity & collaboration (Teams, Slack, Office, Docker)
- **personal** - Entertainment & creative (Spotify, Adobe, Figma)
- **minimal** - Clean slate, build your own
- **custom** - DIY profile

## Machine Types

- **macbook** - General MacBook (battery optimized)
- **macbook-pro** - MacBook Pro (performance focused)
- **macmini** - Desktop (multi-display, high power)
- **vm** - Virtual Machine (minimal, fast)

## File Locations

```
~/.config/nixpkgs/                      # Main config
├── flake.nix                           # Machine list
├── nix/hosts/machines/<hostname>/default.nix        # Your config
└── nix/modules/darwin/apps/installations.nix  # Base apps
```

## Tips

💡 **Use fzf** for best experience: `nix-me add tool fzf && nix-me switch`

💡 **Test first**: `nix-me build` before `nix-me switch`

💡 **Tab to multi-select** in browse mode

💡 **Git commit** before major changes

💡 **Check doctor** if issues: `nix-me doctor`

## Getting Help

```bash
nix-me help           # Full help
nix-me doctor         # Diagnostics
nix-me status         # Current state
```

## Example Session

```bash
# Setup
$ nix-me create
> Hostname: work-mac
> Type: macbook-pro
> Profile: work
✓ Configuration created!

# Add apps
$ nix-me browse
> (Select apps with TAB)
✓ 5 apps selected

# Apply
$ nix-me switch
✓ Configuration applied!

# Verify
$ nix-me status
✓ All systems green
```

---

**Full docs:** See [CLI_GUIDE.md](CLI_GUIDE.md) for complete documentation
