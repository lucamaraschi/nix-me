# nix-me Search Functionality Implementation Analysis

## Document Overview
This document provides a comprehensive analysis of how search and interactive package browsing is implemented in the nix-me tool, focusing on understanding the current implementation to fix the two identified issues.

---

## 1. SEARCH HANDLING AND ENTRY POINTS

### 1.1 Main Entry Point: `bin/nix-me` 

**File:** `/Users/batman/src/lm/nix-me/bin/nix-me` (Lines 157-200)

The main search handler is `cmd_search()`:

```bash
cmd_search() {
    local query="$1"
    
    # Validation: query must be provided
    if [ -z "$query" ]; then
        print_error "Please provide a search term"
        echo "Usage: nix-me search <query>"
        return 1
    fi
    
    # Fallback if fzf not available
    if ! command -v fzf &>/dev/null; then
        print_warn "fzf not available, showing simple results"
        brew search --cask "$query" 2>/dev/null | head -20
        return 0
    fi
    
    # Main search path: uses fzf for interactive browsing
    local selected=$(browse_homebrew_casks_fzf "$query")
    
    # ... processes selection and adds to config
}
```

**Key Entry Points:**
- `nix-me search <query>` - Enters search mode with query
- `nix-me browse` - Interactive browser with menu
- `nix-me add app <name>` - Calls `cmd_search` internally

### 1.2 The Browse Entry Point: `cmd_browse()`

**File:** `/Users/batman/src/lm/nix-me/bin/nix-me` (Lines 96-155)

Provides a menu-driven interface with three search modes:

```bash
cmd_browse() {
    # Shows menu:
    echo "  ${CYAN}1${NC}) Browse all applications"
    echo "  ${CYAN}2${NC}) Browse by category"
    echo "  ${CYAN}3${NC}) Search specific apps"
    
    # Routes to:
    # - browse_homebrew_casks_fzf("")        → all apps
    # - browse_by_category()                  → categories
    # - browse_homebrew_casks_fzf("$query")  → search
}
```

---

## 2. SEARCH PROCESS MANAGEMENT

### 2.1 Core Search Function: `browse_homebrew_casks_fzf()`

**File:** `/Users/batman/src/lm/nix-me/lib/package-manager.sh` (Lines 50-182)

This is the main search implementation with fzf integration:

```bash
browse_homebrew_casks_fzf() {
    local query="${1:-}"
    
    # 1. VALIDATION PHASE
    if ! has_fzf; then
        print_error "fzf is not installed..."
        return 1
    fi
    
    # 2. DATA PREPARATION PHASE
    print_header "Browse Homebrew Applications"
    print_info "Searching for applications..."
    
    # Get installed casks for status display
    local installed_casks=$(brew list --cask 2>/dev/null | sort)
    
    # Create temp files
    local temp_file=$(mktemp)
    local formatted_file=$(mktemp)
    
    # 3. SEARCH QUERY PHASE
    if [ -n "$query" ]; then
        # Use brew search for query
        brew search --casks "$query" 2>/dev/null | grep -v "^==" > "$temp_file"
    else
        # Load popular apps from hardcoded list
        cat > "$temp_file" << 'EOF'
        visual-studio-code
        docker
        google-chrome
        ... (130+ apps)
        EOF
    fi
    
    # 4. FORMATTING PHASE
    # Format output with green tick for installed packages
    while IFS= read -r cask; do
        if echo "$installed_casks" | grep -q "^${cask}$"; then
            echo -e "\033[0;32m✓\033[0m $cask" >> "$formatted_file"
        else
            echo "  $cask" >> "$formatted_file"
        fi
    done < "$temp_file"
    
    # 5. FZF INTERACTIVE PHASE
    local selected=$(cat "$formatted_file" | fzf \
        --multi \                           # Multi-select enabled
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
    
    # Cleanup temp files
    rm "$temp_file"
    rm "$formatted_file"
    
    # 6. RESULT PROCESSING PHASE
    if [ -z "$selected" ]; then
        print_info "No selection made"
        return 0
    fi
    
    # Extract package names (remove formatting)
    local cleaned_selected=$(echo "$selected" | \
        sed 's/^[[:space:]]*✓[[:space:]]*//' | \
        sed 's/^[[:space:]]*//');
    
    echo "$cleaned_selected"
}
```

### 2.2 Process Flow in fzf Preview

**Critical Detail:** Line 162 in package-manager.sh

```bash
--preview="brew info --cask {2} 2>/dev/null | head -10" \
```

This is where the preview panel is powered by running `brew info --cask` for EACH preview interaction.

**The Issue:** 
- `brew info --cask` is a subprocess call that runs DURING the fzf interaction
- When user searches in fzf, each keystroke may trigger preview updates
- Each preview update spawns a `brew info` process
- These processes are not managed - they accumulate if search is slow

### 2.3 Process Management Analysis

**Current State:** NO active process management

Looking through all files:
- ❌ No background process tracking
- ❌ No process cleanup on search cancellation (ESC)
- ❌ No process limits or timeouts
- ❌ fzf is not daemonized
- ❌ No signal handlers for SIGTERM/SIGKILL

**Where Multiple Processes Could Pile Up:**

1. User starts search: `nix-me search docker`
2. fzf starts with `browse_homebrew_casks_fzf "docker"`
3. fzf loads with preview pane
4. User types more filter characters: "k", "e", "r"
5. Each character keystroke triggers preview update
6. Each preview = new `brew info --cask` subprocess
7. If user cancels (ESC) or searches again, old processes may still be running

---

## 3. DETAILS PANEL IMPLEMENTATION

### 3.1 Current Preview Implementation

**File:** `/Users/batman/src/lm/nix-me/lib/package-manager.sh` (Line 162)

The details/preview panel is implemented using fzf's `--preview` flag:

```bash
--preview="brew info --cask {2} 2>/dev/null | head -10" \
--preview-window=right:50%:wrap \
```

**How it works:**
1. `{2}` - fzf token for the 2nd column (package name)
2. Command: `brew info --cask <package>` - Fetches cask information
3. Pipes to `head -10` - Shows first 10 lines
4. Displays in right pane (50% width)
5. Updates when user navigates

### 3.2 What `brew info --cask` Returns

For installed packages:
```
spotify: Music and Podcast Streaming Service
/opt/homebrew/Caskroom/spotify/latest
From: https://github.com/Homebrew/homebrew-casks/blob/HEAD/Casks/s/spotify.rb
==> Name
Spotify
==> Description
Music and Podcast Streaming Service
==> Artifacts
...
```

For non-installed packages:
```
docker: Containerization platform
==> Name
Docker
==> Description
Containerization platform
==> Homepage
https://www.docker.com
...
```

### 3.3 THE CORE ISSUE: Non-Installed Package Details

**Problem Location:** Lines 140-149 of package-manager.sh

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

This creates output like:
```
✓ spotify
  docker
  visual-studio-code
```

**When fzf preview runs:**
```bash
--preview="brew info --cask {2} 2>/dev/null | head -10" \
```

The `{2}` token tries to extract the 2nd column. For lines starting with "✓ ", the formatting works. For lines with just spaces, it fails to extract properly.

**Why Non-Installed Details Don't Show:**
1. The line formatting with leading spaces breaks token extraction
2. `{2}` in fzf tries to get 2nd column, but gets nothing or wrong content
3. `brew info` runs on empty string or wrong package name
4. Preview shows error or nothing

---

## 4. INSTALLED vs NON-INSTALLED PACKAGE HANDLING

### 4.1 Current Status Detection

**File:** `/Users/batman/src/lm/nix-me/lib/package-manager.sh` (Lines 62-63)

```bash
# Get list of installed casks
local installed_casks=$(brew list --cask 2>/dev/null | sort)
```

This gets the list ONCE at function start and stores it.

### 4.2 How Status is Determined

**For Browse Operation:**
```bash
# Check if installed
if echo "$installed_casks" | grep -q "^${cask}$"; then
    echo -e "\033[0;32m✓\033[0m $cask" >> "$formatted_file"  # Installed
else
    echo "  $cask" >> "$formatted_file"                        # Not installed
fi
```

### 4.3 Status Information in Other Commands

**In cmd_search() and cmd_browse()** (Lines 179-187 of bin/nix-me):

```bash
print_info "Selected ${#packages[@]} apps:"
for pkg in "${packages[@]}"; do
    if echo "$installed_casks" | grep -q "^${pkg}$"; then
        echo -e "  ${GREEN}✓${NC} $pkg ${YELLOW}(already installed)${NC}"
    else
        echo "  ${GREEN}•${NC} $pkg"
    fi
done
```

This shows status AFTER selection, but not in the details panel during selection.

### 4.4 Missing Functionality: Installation Status in Details

The details panel (fzf preview) does NOT show:
- ❌ Whether package is installed
- ❌ Version information
- ❌ Installation path
- ❌ Why preview might fail for non-installed packages

---

## 5. ARCHITECTURE SUMMARY

### 5.1 Component Diagram

```
nix-me CLI (bin/nix-me)
    │
    ├─→ cmd_browse()
    │   └─→ browse_homebrew_casks_fzf("")
    │
    ├─→ cmd_search(query)
    │   └─→ browse_homebrew_casks_fzf("query")
    │
    └─→ cmd_add_app(name)
        └─→ cmd_search(name)

package-manager.sh Functions
    │
    ├─→ browse_homebrew_casks_fzf(query)
    │   │
    │   ├─ Get installed_casks list (brew list --cask)
    │   ├─ Create temp files
    │   ├─ Populate with search results (brew search --casks)
    │   ├─ Format output with ✓ and spacing
    │   ├─ Launch fzf with:
    │   │   ├─ Multi-select enabled
    │   │   ├─ Preview: brew info --cask {2}
    │   │   ├─ Keybindings: TAB, ENTER, ESC, Ctrl+A, Ctrl+D
    │   │   └─ Colors and formatting
    │   ├─ Cleanup temp files
    │   └─ Return cleaned selection
    │
    └─→ add_casks_to_config(hostname, casks...)
        └─ Updates configuration file
```

### 5.2 Data Flow

```
User Input (query or browse)
    ↓
brew search --casks <query>
    ↓
Create formatted list with ✓ for installed
    ↓
fzf --multi --preview="brew info --cask {2}"
    ↓
[User selects with TAB]
    ↓
User presses ENTER
    ↓
Extract package names
    ↓
Ask to add to config? Y/N
    ↓
add_casks_to_config()
    ↓
Update .nix file
    ↓
Ask to apply now? Y/N
    ↓
nix-me switch (if yes)
```

---

## 6. IDENTIFIED ISSUES & ROOT CAUSES

### Issue #1: Search Aborting on New Search

**Problem:** When user searches for one set of packages, then starts a NEW search, the first search's processes don't get cleaned up.

**Root Cause:**
1. `browse_homebrew_casks_fzf()` creates temp files with `mktemp`
2. These are cleaned up at the END of the function
3. BUT if user presses ESC and then starts a new search, the OLD `brew info` subprocesses from the old fzf instance may still be running
4. These zombie processes accumulate and can cause fzf to hang or behave erratically

**Code Location:** Lines 169-170 of package-manager.sh

```bash
rm "$temp_file"
rm "$formatted_file"
```

The cleanup happens AFTER fzf exits, but subprocesses spawned by fzf may outlive fzf.

**Impact:**
- Multiple concurrent fzf instances
- Multiple concurrent `brew info` calls
- System resource exhaustion
- Potential deadlock in preview generation

---

### Issue #2: Non-Installed Packages Don't Show Details

**Problem:** When browsing packages, non-installed packages don't show preview/details information in the details panel.

**Root Cause:**

The fzf preview command uses `{2}` token to extract package name:
```bash
--preview="brew info --cask {2} 2>/dev/null | head -10"
```

But the formatted output for non-installed packages is:
```
  docker          ← starts with two spaces
```

While installed packages are:
```
✓ spotify        ← starts with tick and space
```

When fzf tries to extract `{2}` (2nd whitespace-separated field):
- For "✓ spotify" → gets "spotify" ✓
- For "  docker" → gets nothing or empty string ✗

So the preview runs: `brew info --cask` (no argument) or with wrong package name.

**Code Locations:**
- Lines 140-149: Formatting that adds inconsistent spacing
- Line 162: Preview command with `{2}` token

**Impact:**
- Users can't see what non-installed packages do
- Users have to remember what packages do
- Higher chance of selecting wrong packages
- Poor user experience

---

## 7. RECOMMENDATIONS FOR FIXES

### Fix #1: Process Management for Search Operations

**Solution:** Implement process tracking and cleanup:

1. Add signal handlers (SIGTERM, SIGINT) to kill child processes
2. Store fzf process ID and kill it when needed
3. Add process timeout for `brew info` calls
4. Implement process pooling to limit concurrent calls

**Implementation Pattern:**
```bash
# Track fzf PID
local fzf_pid
fzf ... &
fzf_pid=$!

# Trap signals to kill child processes
trap "kill $fzf_pid 2>/dev/null" EXIT SIGINT SIGTERM

# Wait for fzf completion
wait $fzf_pid

# Cleanup
trap - EXIT SIGINT SIGTERM
```

---

### Fix #2: Consistent Package Formatting for Preview

**Solution:** Use consistent output format for both installed and non-installed:

1. Use a delimiter that fzf can reliably parse (e.g., `|`)
2. Separate visual indicator from package name
3. Ensure `{2}` always extracts the package name

**Implementation Pattern:**
```bash
# Instead of:
echo -e "\033[0;32m✓\033[0m $cask"     # Installed
echo "  $cask"                          # Not installed

# Use:
echo "✓ | $cask"                        # Installed
echo "  | $cask"                        # Not installed

# Then in fzf preview:
--preview="brew info --cask {3} 2>/dev/null | head -10"
```

Or use a more robust approach:

```bash
echo "✓|$cask"    # Installed
echo " |$cask"    # Not installed

# Then:
--preview="brew info --cask {2} 2>/dev/null | head -10"
```

---

## 8. FILE STRUCTURE REFERENCE

### Main Files Involved

```
nix-me/
├── bin/
│   └── nix-me                      # Main entry point, CLI routing
│                                   # Lines 96-200: browse/search handlers
│
├── lib/
│   ├── ui.sh                       # UI helpers (colors, prompts)
│   ├── package-manager.sh          # Search implementation
│   │                               # Lines 50-182: browse_homebrew_casks_fzf()
│   │                               # Lines 249-354: add_casks_to_config()
│   │
│   ├── config-wizard.sh            # Wizard orchestration
│   ├── config-builder.sh           # Configuration generation
│   └── wizard.sh                   # Profile selection
│
└── hosts/
    └── profiles/
        ├── work.nix
        └── personal.nix
```

### Key Function Map

```
Entry Points:
- nix-me search <query>         → cmd_search()          [bin/nix-me:157]
- nix-me browse                 → cmd_browse()          [bin/nix-me:96]
- nix-me add app <name>         → cmd_add_app()         [bin/nix-me:202]

Implementation:
- browse_homebrew_casks_fzf()   [lib/package-manager.sh:50]
- browse_by_category()          [lib/package-manager.sh:369]
- search_homebrew_casks()       [lib/package-manager.sh:28]
- add_casks_to_config()         [lib/package-manager.sh:250]

Helpers:
- has_fzf()                     [lib/package-manager.sh:18]
- get_cask_description()        [lib/package-manager.sh:44]
```

---

## 9. TESTING NOTES

### How to Reproduce Issue #1

```bash
# 1. Start first search
nix-me search docker
# Let it load, then ESC to cancel

# 2. Immediately start another search
nix-me search spotify
# If previous processes are lingering, this may hang or behave oddly

# 3. Check processes
ps aux | grep brew
ps aux | grep fzf
# Should show lingering processes from first search
```

### How to Reproduce Issue #2

```bash
# 1. Start browse
nix-me browse
# Choose option 1: Browse all

# 2. Search for an app that's NOT installed
# Type "zoom" and navigate to it

# 3. Look at preview panel
# Should show: "zoom: Video conferencing"
# Currently shows: Nothing or error

# 4. Compare with installed app
# Type "spotify" (if installed)
# Preview shows details correctly
```

---

## 10. SUMMARY TABLE

| Aspect | Current State | Issue | Impact |
|--------|---------------|-------|--------|
| **Search Handler** | `cmd_search()` in bin/nix-me | Routes to `browse_homebrew_casks_fzf()` | Works for simple searches |
| **Process Management** | None | No cleanup on cancellation | Accumulates zombie processes |
| **Preview Panel** | `brew info --cask {2}` | Token extraction fails for non-installed | No details for uninstalled packages |
| **Installed Status** | Shows ✓ in list | Formatting breaks fzf token extraction | Preview broken for non-installed |
| **Temp File Cleanup** | Cleanup at function end | But subprocesses may outlive cleanup | Resource leaks |
| **Error Handling** | Limited | No trap handlers for signals | Unclean shutdown |
| **User Experience** | Mostly good | Two critical issues | Can't browse freely |

---

## CONCLUSION

The nix-me search functionality is well-architected but has two specific implementation issues:

1. **Process Management Gap:** No active tracking/cleanup of subprocess hierarchies from fzf and brew commands
2. **Output Formatting Gap:** Inconsistent formatting of installed vs non-installed packages breaks fzf's field extraction

Both are addressable with targeted fixes in `lib/package-manager.sh` without major architectural changes.

