# nix-me Search Implementation - Code Reference Guide

## Quick Code Locations

### Issue #1: Process Management Problem

**File:** `/Users/batman/src/lm/nix-me/lib/package-manager.sh`

**Problem Area:**
- Lines 50-182: `browse_homebrew_casks_fzf()` function
- Line 156-167: fzf invocation WITHOUT process tracking
- Lines 169-170: Cleanup happens AFTER fzf exits

**Current Code (Lines 156-170):**
```bash
# Use fzf for selection with preview
print_info "Use arrow keys to browse, TAB to select multiple, ENTER to confirm"
print_info "Green tick (✓) indicates already installed packages"
echo ""

local selected=$(cat "$formatted_file" | fzf \
    --multi \
    --height=80% \
    --border=rounded \
    --prompt="Select apps > " \
    --header="✓ = installed | TAB: select multiple | ENTER: confirm | ESC: cancel" \
    --preview="brew info --cask {2} 2>/dev/null | head -10" \
    --preview-window=right:50%:wrap \
    --bind="ctrl-a:select-all,ctrl-d:deselect-all" \
    --color="header:italic:cyan" \
    --ansi \
)

rm "$temp_file"
rm "$formatted_file"
```

**Problem:** No signal handlers or PID tracking before launching fzf

**Why It Fails:**
1. fzf starts and spawns preview subprocesses
2. Each preview keystroke spawns new `brew info` subprocess
3. User presses ESC to cancel (or starts new search)
4. function returns, cleanup happens
5. BUT: old `brew info` processes may still be running in background
6. New search finds old processes still consuming resources

---

### Issue #2: Non-Installed Package Details Problem

**File:** `/Users/batman/src/lm/nix-me/lib/package-manager.sh`

**Problem Area #1 - Formatting (Lines 140-149):**
```bash
# Format casks with green tick for installed packages
while IFS= read -r cask; do
    if echo "$installed_casks" | grep -q "^${cask}$"; then
        # Installed - add green tick
        echo -e "\033[0;32m✓\033[0m $cask" >> "$formatted_file"
    else
        # Not installed - add spacing
        echo "  $cask" >> "$formatted_file"
    fi
done < "$temp_file"
```

**Problem:** Creates inconsistent spacing:
- Installed: `✓ spotify` (starts with ANSI code + tick + space)
- Not installed: `  docker` (starts with TWO spaces)

**Problem Area #2 - Preview (Line 162):**
```bash
--preview="brew info --cask {2} 2>/dev/null | head -10" \
```

**How fzf Token Extraction Works:**
- `{2}` = 2nd whitespace-separated column
- For "✓ spotify" → splits to ["✓", "spotify"] → {2} = "spotify" ✓
- For "  docker" → splits to ["", "", "docker"] → {2} = "" ✗

**Why Preview Fails:**
1. fzf sees "  docker" (two spaces before package name)
2. Tries to extract {2} (2nd field)
3. Gets empty string or wrong field
4. Runs `brew info --cask ` (missing package name)
5. Preview shows error or blank

---

## File Structure and Function Map

### Entry Point: `/Users/batman/src/lm/nix-me/bin/nix-me`

**cmd_search() - Lines 157-200:**
```bash
cmd_search() {
    local query="$1"
    # ... validation ...
    local selected=$(browse_homebrew_casks_fzf "$query")  # LINE 172
    # ... handles result ...
}
```

**cmd_browse() - Lines 96-155:**
```bash
cmd_browse() {
    # Shows menu, then routes to:
    # browse_homebrew_casks_fzf("")          # Browse all
    # browse_by_category()                   # Categories  
    # browse_homebrew_casks_fzf("$query")   # Search
}
```

**Calls to package-manager.sh functions:**
- Line 116: `browse_homebrew_casks_fzf ""`
- Line 119: `browse_by_category`
- Line 123: `browse_homebrew_casks_fzf "$query"`
- Line 172: `browse_homebrew_casks_fzf "$query"`
- Line 193: `add_casks_to_config "$hostname" "${packages[@]}"`

---

### Core Implementation: `/Users/batman/src/lm/nix-me/lib/package-manager.sh`

**browse_homebrew_casks_fzf() - Lines 50-182:**

```
Phase 1: Validation (Lines 53-56)
├─ Check fzf availability
│
Phase 2: Data Prep (Lines 58-63)
├─ Print header
├─ Get installed casks list
├─ Create temp files
│
Phase 3: Search Query (Lines 69-132)
├─ If query: brew search --casks "$query"
├─ Else: Load popular apps from hardcoded list
│
Phase 4: Formatting (Lines 140-149)
├─ Loop through results
├─ Add ✓ if installed
├─ Add spaces if not installed
│
Phase 5: FZF Interactive (Lines 156-167)
├─ Launch fzf with preview
├─ NO PROCESS TRACKING ← ISSUE #1
├─ Preview with {2} token ← ISSUE #2
│
Phase 6: Cleanup (Lines 169-170)
├─ Remove temp files
│
Phase 7: Result Processing (Lines 172-182)
├─ Extract package names
├─ Return cleaned results
```

**Key Lines:**
- Line 63: `local installed_casks=$(brew list --cask 2>/dev/null | sort)`
- Lines 140-149: Formatting loop (INCONSISTENT SPACING)
- Line 156-167: fzf launch (NO PROCESS TRACKING)
- Line 162: `--preview="brew info --cask {2} 2>/dev/null | head -10"` (BROKEN TOKEN)
- Lines 169-170: Cleanup happens too late

---

**browse_by_category() - Lines 369-438:**

```bash
# Routes category selection to browse_homebrew_casks_fzf() with search term
case "$category_name" in
    "Development")
        browse_homebrew_casks_fzf "code docker postman tableplus"
        ;;
    # ... more categories ...
esac
```

---

**add_casks_to_config() - Lines 250-354:**

```bash
# Called after user selects packages
# Updates .nix configuration file
# Prompts to apply changes
```

---

## Critical Code Sequences

### How Preview Breaks (Issue #2)

**Input:** "  docker" (two spaces, then package name)

**fzf Processing:**
```
1. Line value: "  docker"
2. fzf sees whitespace-separated fields: ["", "", "docker"]
3. User hovers over this line
4. fzf extracts {2} (2nd field) = "" (empty)
5. Executes: brew info --cask 2>/dev/null
6. brew complains: "Error: No cask found"
7. Preview shows error
```

**Compare - Installed Package (Works):**
```
1. Line value: "✓ spotify" (after ANSI formatting)
2. fzf sees fields: ["✓", "spotify"]
3. User hovers over this line
4. fzf extracts {2} (2nd field) = "spotify"
5. Executes: brew info --cask spotify 2>/dev/null
6. Returns cask info successfully
7. Preview shows details
```

---

### How Process Accumulation Happens (Issue #1)

**Sequence:**
```
1. User: nix-me search docker
2. bash executes: browse_homebrew_casks_fzf "docker"
3. fzf launches, PID 12345
4. fzf spawns preview process: brew info --cask docker
5. User starts typing to filter: types "k"
6. Preview updates, spawns: brew info --cask dock... (different query)
7. Preview processes may still be running
8. User presses ESC
9. function returns, cleanup at lines 169-170
10. BUT: brew processes from step 4-6 may still be in process queue
11. User: nix-me search spotify
12. Step 3 repeats, but old brew processes still exist
13. System accumulates processes
```

---

## Detailed Problem Explanation

### Problem #1: Missing Process Tracking

**Current Implementation (Line 156-167):**
```bash
local selected=$(cat "$formatted_file" | fzf \
    --multi \
    --height=80% \
    --border=rounded \
    --prompt="Select apps > " \
    --header="✓ = installed | TAB: select multiple | ENTER: confirm | ESC: cancel" \
    --preview="brew info --cask {2} 2>/dev/null | head -10" \
    --preview-window=right:50%:wrap \
    --bind="ctrl-a:select-all,ctrl-d:deselect-all" \
    --color="header:italic:cyan" \
    --ansi \
)
```

**What's Missing:**
1. No PID capture before launching fzf
2. No trap handlers for SIGTERM/SIGINT
3. No wait() for child processes
4. No timeout mechanism

**Result:**
- fzf starts without process tracking
- Preview subprocesses are "orphaned"
- If user cancels (ESC), fzf exits but processes may remain
- Next search finds these lingering processes

---

### Problem #2: Token Extraction Failure

**Root Cause Chain:**

```
Lines 140-149 create INCONSISTENT OUTPUT
    ↓
Installed: "✓ spotify" (visual tick + space + name)
Not Installed: "  docker" (two spaces + name)
    ↓
Line 162 tries to extract field {2}
    ↓
✓ spotify → splits to ["✓", "spotify"] → {2} = "spotify" ✓
  docker → splits to ["", "", "docker"] → {2} = "" ✗
    ↓
fzf executes: brew info --cask spotify (works)
fzf executes: brew info --cask (FAILS)
    ↓
Installed packages: Preview shows details ✓
Non-installed packages: Preview shows error/blank ✗
```

---

## Testing the Issues

### Reproduce Issue #1 (Process Accumulation)

```bash
# Terminal 1: Watch processes
watch -n 0.5 "ps aux | grep -E 'brew|fzf' | grep -v grep"

# Terminal 2: Trigger the issue
cd /Users/batman/src/lm/nix-me

# Start search 1
bin/nix-me search docker
# Wait for fzf to load
# Press ESC to cancel

# Start search 2
bin/nix-me search spotify
# Watch terminal 1 - should see lingering processes from search 1

# Repeat
bin/nix-me search figma
# More processes accumulate
```

### Reproduce Issue #2 (Missing Preview)

```bash
cd /Users/batman/src/lm/nix-me

# Start browse
bin/nix-me browse

# Choose option 1: Browse all

# Type to filter: "zoom"
# Navigate to: "  zoom" (non-installed)
# Look at preview pane on right
# Should show: "Zoom: Video conferencing"
# Actually shows: Empty or error

# Type to filter: "spotify" 
# If installed, preview shows details correctly
```

---

## Summary of Changes Needed

### For Issue #1 (Process Management):

**Location:** Lines 156-170 in `/Users/batman/src/lm/nix-me/lib/package-manager.sh`

**Add before launching fzf:**
1. Trap signal handlers
2. Capture fzf PID
3. Add kill signal on exit

**Add timeout mechanism:**
1. Kill preview processes if they exceed timeout
2. Limit concurrent preview processes

---

### For Issue #2 (Token Extraction):

**Location:** Lines 140-149 and 162 in `/Users/batman/src/lm/nix-me/lib/package-manager.sh`

**Option A: Change separator**
```bash
# Instead of spaces, use pipe separator
echo "✓|$cask"        # Installed
echo " |$cask"        # Not installed

# Update preview to use correct field
--preview="brew info --cask {2} 2>/dev/null | head -10"
```

**Option B: Use consistent spacing**
```bash
# Use consistent column positions
printf "%-1s %s\n" "✓" "$cask"   # Installed
printf "%-1s %s\n" " " "$cask"   # Not installed

# Update preview token accordingly
```

**Option C: Use field reference**
```bash
# Extract just the cask name, ignoring prefix
--preview="echo {} | sed 's/^[[:space:]*✓[[:space:]]*//' | xargs brew info --cask 2>/dev/null | head -10"
```

---

## File Dependencies

```
bin/nix-me
    ↑
    └─ sources lib/ui.sh (line 10)
    └─ sources lib/package-manager.sh (line 12)
       └─ imports lib/ui.sh (line 6 in package-manager.sh)
    └─ sources lib/config-builder.sh (line 11)
    └─ sources lib/config-wizard.sh (line 13)

lib/package-manager.sh
    └─ calls browse_homebrew_casks_fzf() [main issue location]
    └─ calls add_casks_to_config()
    └─ calls browse_by_category()
    └─ external commands: fzf, brew, mktemp, grep, sed, awk
```

---

## Next Steps

1. **For Fix #1:** Add process tracking to lines 156-170
   - Implement signal handlers
   - Track fzf PID
   - Clean up preview processes on exit

2. **For Fix #2:** Update lines 140-149 and 162
   - Change output format to use consistent delimiter
   - Update fzf preview token to match new format
   - Verify preview works for both installed and non-installed

3. **Testing:**
   - Test both issues don't occur
   - Verify preview shows details for non-installed packages
   - Verify multiple searches don't accumulate processes

