# Quick Start Testing Guide

## ✅ Basic Tests Passed!

Your nix-me CLI is ready. Here's how to test each feature:

## 1. Test CLI Commands (2 minutes)

```bash
# Display help
bin/nix-me help

# Show system status
bin/nix-me status

# Run diagnostics
bin/nix-me doctor

# List installed packages
bin/nix-me list
```

Expected: Colorful output, no errors.

## 2. Test Interactive Search (3 minutes)

**Requires fzf** (you have it! ✓)

```bash
# Search for Docker apps
bin/nix-me search docker
```

**What you'll see:**
```
┌─────────────────────────────────────────┐
│ Select apps > docker                     │
├─────────────────────────────────────────┤
│ > docker                                 │
│   docker-desktop                         │
│   orbstack                               │
└─────────────────────────────────────────┘
```

**What to try:**
- Type to filter (e.g., type "desktop")
- Use ↑↓ arrows to navigate
- Press TAB to select/deselect
- Press ESC to cancel (won't apply anything)

**Safe testing:** Just press ESC to cancel. Nothing will be changed.

## 3. Test Browse Command (5 minutes)

```bash
bin/nix-me browse
```

**You'll see menu:**
```
Browse Applications

  1) Browse all applications
  2) Browse by category
  3) Search specific apps

Choice [1]:
```

**Try each option:**

**Option 1:** Browse all
- Shows popular apps in fzf
- TAB to select multiple
- ESC to cancel

**Option 2:** Category browsing
- Select category (Development, Design, etc.)
- Browse filtered apps
- ESC to cancel

**Option 3:** Search
- Enter search term (e.g., "spotify")
- Browse results
- ESC to cancel

## 4. Test Configuration Wizard (10 minutes)

**SAFE MODE** - Creates test config, doesn't touch your real one:

```bash
./tests/test-wizard.sh
```

**Follow prompts:**
1. **Hostname:** test-machine
2. **Username:** batman (or your username)
3. **Display Name:** Test Machine
4. **Machine Type:** Choose 2 (macbook-pro)
5. **Profile:** Choose 1 (work)
6. **Apps:**
   - Choose option 4 (skip) for now
   - OR try browsing and press ESC

**Result:** Creates config in `/tmp`, shows you what would be generated.

## 5. Test Real Wizard (Optional)

If you want to create an actual test configuration:

```bash
bin/nix-me create
```

**This will:**
- Create real configuration files
- Ask if you want to apply
- You can say "no" at the end to review first

**Suggested test values:**
- Hostname: `test-config`
- Type: `macbook-pro`
- Profile: `minimal` (fewest apps to install)
- Apps: Skip or select just 1-2

**To clean up after:**
```bash
rm -rf ~/.config/nixpkgs/hosts/test-config
# Remove from flake.nix
```

## 6. Visual Test Examples

### Example 1: Search for Spotify
```bash
bin/nix-me search spotify
```

```
┌───────────────────────────────────────────────┐
│ Select apps > spotify                  1/342  │
├───────────────────────────────────────────────┤
│ > spotify                                     │
└───────────────────────────────────────────────┘
  TAB: select | ENTER: confirm | ESC: cancel

Preview:
spotify: Music streaming service
```

### Example 2: Browse Development Category
```bash
bin/nix-me browse
# Choose 2: Browse by category
```

```
┌───────────────────────────────────────────────┐
│ Select category >                      9/9    │
├───────────────────────────────────────────────┤
│ > Development                                 │
│   Design                                      │
│   Productivity                                │
└───────────────────────────────────────────────┘

Development: Visual Studio Code, Docker, Git clients, IDEs
```

Select Development, then see:
```
┌───────────────────────────────────────────────┐
│ Select apps >                          42/342 │
├───────────────────────────────────────────────┤
│   visual-studio-code                          │
│ > docker-desktop                              │
│   github                                      │
│   postman                                     │
└───────────────────────────────────────────────┘
```

## 7. Test Profile Files

View the profile configurations:

```bash
# Work profile
cat hosts/profiles/work.nix

# Personal profile
cat hosts/profiles/personal.nix

# MacBook Pro settings
cat hosts/macbook-pro/default.nix
```

## 8. Test Documentation

All docs are ready:

```bash
# Complete CLI guide
cat docs/CLI_GUIDE.md

# Quick reference
cat docs/QUICK_REFERENCE.md

# Profile guide
cat docs/PROFILES.md

# Interactive examples
cat DEMO.md

# Feature summary
cat NEW_FEATURES.md
```

## Interactive Testing Checklist

Copy this and check off as you test:

```
Basic Commands:
[ ] bin/nix-me help - Displays colored help
[ ] bin/nix-me status - Shows system info
[ ] bin/nix-me doctor - Runs diagnostics
[ ] bin/nix-me list - Lists packages

Search & Browse:
[ ] bin/nix-me search docker - Opens fzf with results
[ ] Type to filter - Filters work
[ ] Arrow keys - Navigate works
[ ] TAB key - Selects/deselects
[ ] ESC - Cancels safely
[ ] bin/nix-me browse - Shows menu
[ ] Option 1 - Browse all apps
[ ] Option 2 - Browse by category
[ ] Option 3 - Search specific apps

Category Browse:
[ ] Development category - Shows dev apps
[ ] Design category - Shows design apps
[ ] Preview pane - Shows descriptions

Wizard:
[ ] ./tests/test-wizard.sh - Safe test mode works
[ ] Hostname prompt - Accepts input
[ ] Machine type - Shows options
[ ] Profile selection - Shows 4 profiles
[ ] Package browse - fzf appears (or skip)
[ ] Summary - Shows config
[ ] Creates files in /tmp

Profile Files:
[ ] Work profile exists - Has Teams, Docker, etc.
[ ] Personal profile exists - Has Spotify, OBS, etc.
[ ] MacBook Pro type - Has Pro settings

Documentation:
[ ] CLI_GUIDE.md - Complete reference
[ ] QUICK_REFERENCE.md - Command list
[ ] PROFILES.md - Profile guide
[ ] DEMO.md - Examples
[ ] TESTING.md - Test guide
```

## Troubleshooting

### "brew: command not found"
```bash
# Homebrew is required for package browsing
# Install from: https://brew.sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### "fzf: command not found"
```bash
# Install fzf for interactive features
brew install fzf

# Or use Nix temporarily
nix-shell -p fzf --run "bin/nix-me browse"
```

### Colors not showing
Your terminal may not support ANSI colors. Try:
- iTerm2 (recommended for macOS)
- Terminal.app with TERM=xterm-256color

### Libraries won't load
```bash
# Check permissions
chmod +x lib/*.sh
chmod +x bin/nix-me
```

## What's Safe vs What Changes Things

### ✅ SAFE (Read-only):
- `bin/nix-me help`
- `bin/nix-me status`
- `bin/nix-me doctor`
- `bin/nix-me list`
- `bin/nix-me diff`
- `bin/nix-me search <query>` + ESC
- `bin/nix-me browse` + ESC
- `./tests/test-wizard.sh` (uses /tmp)

### ⚠️ CREATES/MODIFIES:
- `bin/nix-me create` - Creates config files
- `bin/nix-me switch` - Applies configuration
- `bin/nix-me reconfigure` - Modifies configs
- Selecting apps and choosing "Add" (not ESC)

## Quick Demo Flow

**1 minute demo of interactive features:**

```bash
# 1. Show help (5 seconds)
bin/nix-me help

# 2. Search for app (15 seconds)
bin/nix-me search spotify
# Navigate, press ESC

# 3. Browse categories (20 seconds)
bin/nix-me browse
# Choose option 2
# Select Development
# See apps, press ESC

# 4. Show status (10 seconds)
bin/nix-me status

# 5. Run doctor (10 seconds)
bin/nix-me doctor
```

**Done!** You've seen all the interactive features.

## Next Steps

After testing, if everything works:

1. **Try creating a real config:**
   ```bash
   bin/nix-me create
   ```

2. **Browse and add some apps:**
   ```bash
   bin/nix-me browse
   # Select a few apps
   # Say yes to apply
   ```

3. **Check the results:**
   ```bash
   bin/nix-me status
   bin/nix-me list
   ```

## Need Help?

- **TESTING.md** - Complete test guide
- **CLI_GUIDE.md** - Full CLI reference
- **DEMO.md** - Interactive examples

Happy testing! 🎉
