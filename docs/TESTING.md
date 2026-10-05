# Testing Guide for nix-me Interactive CLI

## Testing Approaches

There are three levels of testing for nix-me:

1. **Unit/Component Testing** - Test individual CLI commands and features (this document)
2. **VM Integration Testing** - Full installation testing in isolated VMs (see [VM Testing Guide](./VM_TESTING.md))
3. **Manual Testing** - Interactive testing on your system

### When to Use Each Approach

- **Component Testing**: Quick iteration, testing specific features, daily development
- **VM Testing**: Pre-release validation, testing clean installations, CI/CD pipelines
- **Manual Testing**: Real-world validation, UX testing, exploratory testing

---

## Component Testing

### Prerequisites

Before testing, ensure you have:
- [x] Nix installed
- [x] Homebrew installed
- [ ] fzf installed (optional but recommended)

```bash
# Install fzf if needed
brew install fzf
# OR
nix-shell -p fzf
```

## Safety Notes

✅ **Safe to test:**
- `help`, `status`, `doctor`, `list`, `diff` - Read-only commands
- `browse` with ESC - Cancel before applying
- `search` with ESC - Cancel before applying

⚠️ **Caution:**
- `create` - Will create config files (use test mode)
- `switch` - Applies changes (only after reviewing)
- `reconfigure` - Modifies existing configs

## Test Sequence

### 1. Basic Commands (Safe - 2 minutes)

```bash
cd /Users/batman/src/lm/nix-me

# Test help
apps/cli/bin/nix-me help
# Expected: Colored help text with all commands

# Test status
apps/cli/bin/nix-me status
# Expected: System status display

# Test doctor
apps/cli/bin/nix-me doctor
# Expected: 8 diagnostic checks

# Test list
apps/cli/bin/nix-me list
# Expected: List of installed packages

# Test diff (if git repo)
apps/cli/bin/nix-me diff
# Expected: Shows uncommitted changes
```

### 2. Interactive Browser (Safe with ESC - 5 minutes)

**Test 1: Search functionality**
```bash
# Run the test script
./tests/integration/test-browse.sh

# OR manually:
source lib/ui.sh
source lib/package-manager.sh
browse_homebrew_casks_fzf "docker"

# What to try:
# 1. Type to filter results
# 2. Use arrow keys to navigate
# 3. Press TAB to select/deselect
# 4. Press ESC to cancel (safe)
# 5. Or select some and press ENTER to see next step
```

**Test 2: Browse all apps**
```bash
apps/cli/bin/nix-me browse

# Menu appears:
#   1) Browse all applications
#   2) Browse by category
#   3) Search specific apps

# Try option 1, then ESC to cancel
```

**Test 3: Category browsing**
```bash
apps/cli/bin/nix-me browse

# Choose option 2: Browse by category
# Select a category (e.g., "Development")
# Browse apps, then ESC to cancel
```

### 3. Search Command (Safe with ESC - 3 minutes)

```bash
# Search for specific apps
apps/cli/bin/nix-me search spotify
# Expected: fzf browser with spotify results
# Press ESC to cancel

apps/cli/bin/nix-me search docker
# Expected: fzf browser with docker results
# Press ESC to cancel

apps/cli/bin/nix-me search figma
# Expected: fzf browser with design apps
# Press ESC to cancel
```

### 4. Configuration Wizard (Test Mode - 10 minutes)

Use the safe test script:

```bash
./tests/integration/test-wizard.sh

# Follow the prompts:
# 1. Enter test hostname (e.g., "test-machine")
# 2. Select machine type
# 3. Select profile
# 4. Browse packages (ESC to skip)
# 5. Review summary

# The script creates config in /tmp, not your real config
```

### 5. Profile Selection Test (Safe - 2 minutes)

```bash
# Test profile selection standalone
source lib/ui.sh
source lib/config-wizard.sh

# This will show the profile selection UI
# (it's just display, won't apply anything)

cat nix/hosts/profiles/work.nix
cat nix/hosts/profiles/personal.nix
```

### 6. Reconfigure Command (Read-Only Test - 3 minutes)

```bash
# This will fail gracefully if config doesn't exist
apps/cli/bin/nix-me reconfigure

# Expected: Menu showing:
#   1) Add applications
#   2) Change profile
#   3) Edit configuration file
#   0) Cancel

# Choose 0 to cancel
```

### 7. Integration Test (Optional - Full Flow)

If you want to test the full flow safely:

```bash
# 1. Create a test configuration directory
export TEST_CONFIG="/tmp/nix-me-test-$$"
mkdir -p "$TEST_CONFIG"

# 2. Copy necessary files
cp -r lib "$TEST_CONFIG/../lib"
cp flake.nix "$TEST_CONFIG/"
mkdir -p "$TEST_CONFIG/hosts"
cp -r nix/hosts/profiles "$TEST_CONFIG/nix/hosts/"
cp -r nix/hosts/macbook "$TEST_CONFIG/nix/hosts/"
cp -r nix/hosts/types/shared "$TEST_CONFIG/nix/hosts/"

# 3. Run wizard pointing to test directory
CONFIG_DIR="$TEST_CONFIG" apps/cli/bin/nix-me create

# 4. Review generated config
ls -la "$TEST_CONFIG/nix/hosts/"
cat "$TEST_CONFIG/nix/hosts/*/default.nix"

# 5. Clean up when done
rm -rf "$TEST_CONFIG"
```

## Feature Checklist

Test each feature and check off:

**CLI Basics:**
- [ ] `nix-me help` displays colored help
- [ ] `nix-me status` shows system info
- [ ] `nix-me doctor` runs diagnostics
- [ ] `nix-me list` shows packages
- [ ] `nix-me diff` shows changes (if git repo)

**Interactive Browsing:**
- [ ] fzf interface appears
- [ ] Typing filters results
- [ ] Arrow keys navigate
- [ ] TAB selects/deselects
- [ ] Preview pane shows app info
- [ ] ESC cancels safely
- [ ] ENTER proceeds to next step

**Search:**
- [ ] `nix-me search <query>` opens fzf
- [ ] Results are relevant
- [ ] Multi-select works
- [ ] Can add to config

**Category Browsing:**
- [ ] Categories display correctly
- [ ] Selecting category filters apps
- [ ] Can navigate and select

**Wizard:**
- [ ] Hostname prompt works
- [ ] Username prompt works
- [ ] Machine type selection (fzf or numbered)
- [ ] Profile selection (fzf or numbered)
- [ ] Package selection (optional)
- [ ] Summary displays correctly
- [ ] Config generation works

**Profile System:**
- [ ] Work profile exists
- [ ] Personal profile exists
- [ ] Profiles have correct apps
- [ ] Can view profile contents

## Expected Behavior

### fzf Browser Interface

```
┌─────────────────────────────────────────────────────────────┐
│ Select apps > doc                                    5/342   │
├─────────────────────────────────────────────────────────────┤
│ > docker                                                     │
│   docker-desktop                                             │
│   visual-studio-code                                         │
│   postman                                                    │
└─────────────────────────────────────────────────────────────┘
  TAB: select | ENTER: confirm | ESC: cancel

┌─ Preview ───────────────────────────────────────────────────┐
│ docker-desktop                                               │
│ Docker Desktop - container platform                          │
└─────────────────────────────────────────────────────────────┘
```

### Wizard Flow

```
🎉 nix-me Configuration Wizard

[1/6] Basic Information
Hostname [current]: test-machine
Username [batman]: batman
Display Name [test-machine]: Test Machine

[2/6] Machine Type
  1) macbook
  2) macbook-pro
  3) macmini
  4) vm
Select [1]: 2

[3/6] Profile
  1) work
  2) personal
  3) minimal
Select [1]: 1

[4/6] Application Selection
(fzf browser or skip)

[5/6] Summary
  Hostname: test-machine
  Type: macbook-pro
  Profile: work

[6/6] Generation
✓ Configuration created!
```

## Troubleshooting

### fzf not found
```bash
brew install fzf
# OR
nix-shell -p fzf --run "apps/cli/bin/nix-me browse"
```

### Homebrew not found
```bash
# Ensure Homebrew is in PATH
eval "$(/opt/homebrew/bin/brew shellenv)"  # Apple Silicon
# OR
eval "$(/usr/local/bin/brew shellenv)"     # Intel
```

### Library loading errors
```bash
# Check all libraries exist
ls -la lib/

# Should see:
# ui.sh
# config-builder.sh
# wizard.sh
# config-wizard.sh
# package-manager.sh
```

### Colors not showing
```bash
# Test color support
echo -e "\033[0;32mGreen\033[0m"

# If no color, terminal may not support ANSI codes
```

## Quick Test Script

Run all basic tests at once:

```bash
#!/bin/bash
echo "🧪 Running nix-me tests..."

echo "1. Testing help..."
apps/cli/bin/nix-me help > /dev/null && echo "✓ Help works"

echo "2. Testing status..."
apps/cli/bin/nix-me status > /dev/null && echo "✓ Status works"

echo "3. Testing doctor..."
apps/cli/bin/nix-me doctor > /dev/null && echo "✓ Doctor works"

echo "4. Testing list..."
apps/cli/bin/nix-me list > /dev/null && echo "✓ List works"

echo "5. Checking libraries..."
source lib/ui.sh && echo "✓ ui.sh loads"
source lib/package-manager.sh && echo "✓ package-manager.sh loads"
source lib/config-wizard.sh && echo "✓ config-wizard.sh loads"

echo ""
echo "✅ Basic tests passed!"
echo ""
echo "To test interactive features:"
echo "  ./tests/integration/test-browse.sh    # Test fzf browser"
echo "  ./tests/integration/test-wizard.sh    # Test wizard"
```

Save this as `run-tests.sh` and execute it.

## Next Steps After Testing

Once you've verified everything works:

1. **Commit changes:**
   ```bash
   git add .
   git commit -m "Add interactive CLI with profiles and fzf browser"
   ```

2. **Update main README:**
   ```bash
   # Add new features section
   # Update quick start guide
   # Add screenshots/demos
   ```

3. **Tag release:**
   ```bash
   git tag v2.0.0
   git push --tags
   ```

4. **Deploy:**
   ```bash
   # Users can pull and use immediately
   cd ~/.config/nixpkgs
   git pull
   nix-me browse  # New features available!
   ```

## Support

If you encounter issues during testing:

1. Check this document's troubleshooting section
2. Run `apps/cli/bin/nix-me doctor`
3. Check `docs/CLI_GUIDE.md` for detailed help
4. Review error messages carefully

Happy testing! 🧪
