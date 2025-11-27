#!/bin/bash

# Package diff utility for nix-me
# Shows what will be added/removed/changed before switching

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Get current hostname for flake
get_hostname() {
    if [ -f "$HOME/.config/nixpkgs/.current-hostname" ]; then
        cat "$HOME/.config/nixpkgs/.current-hostname"
    else
        scutil --get LocalHostName
    fi
}

# Get currently installed Homebrew formulas (CLI tools)
get_current_brews() {
    brew list --formula 2>/dev/null | sort || echo ""
}

# Get currently installed Homebrew casks (GUI apps)
get_current_casks() {
    brew list --cask 2>/dev/null | sort || echo ""
}

# Get currently installed Nix packages
get_current_nix_packages() {
    nix-env -q 2>/dev/null | sort || echo ""
}

# Get packages from configuration file
get_config_packages() {
    local config_file="$1"
    local package_type="$2"  # "brews", "casks", or "systemPackages"

    if [ ! -f "$config_file" ]; then
        echo ""
        return
    fi

    case "$package_type" in
        "brews")
            grep -A 100 'brewsToAdd = \[' "$config_file" 2>/dev/null | \
                grep -v '^\s*#' | \
                grep -o '"[^"]*"' | \
                tr -d '"' | \
                sort || echo ""
            ;;
        "casks")
            grep -A 100 'casksToAdd = \[' "$config_file" 2>/dev/null | \
                grep -v '^\s*#' | \
                grep -o '"[^"]*"' | \
                tr -d '"' | \
                sort || echo ""
            ;;
        "systemPackages")
            grep -A 100 'systemPackagesToAdd = \[' "$config_file" 2>/dev/null | \
                grep -v '^\s*#' | \
                grep -o '"[^"]*"' | \
                tr -d '"' | \
                sort || echo ""
            ;;
    esac
}

# Fetch latest from GitHub
fetch_latest() {
    echo -e "${BLUE}Fetching latest from GitHub...${NC}"
    cd "$REPO_DIR"
    git fetch origin main --quiet
    echo -e "${GREEN}✓ Fetched latest changes${NC}"
}

# Compare two lists and show diff
compare_lists() {
    local current_list="$1"
    local new_list="$2"
    local label="$3"

    local additions=$(comm -13 <(echo "$current_list") <(echo "$new_list"))
    local removals=$(comm -23 <(echo "$current_list") <(echo "$new_list"))
    local unchanged=$(comm -12 <(echo "$current_list") <(echo "$new_list"))

    local add_count=$(echo "$additions" | grep -v '^$' | wc -l | tr -d ' ')
    local rem_count=$(echo "$removals" | grep -v '^$' | wc -l | tr -d ' ')
    local unc_count=$(echo "$unchanged" | grep -v '^$' | wc -l | tr -d ' ')

    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}📦 $label${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    if [ "$add_count" -eq 0 ] && [ "$rem_count" -eq 0 ]; then
        echo -e "${YELLOW}No changes${NC}"
        return
    fi

    if [ "$add_count" -gt 0 ]; then
        echo -e "\n${GREEN}✓ Will install ($add_count):${NC}"
        echo "$additions" | grep -v '^$' | sed 's/^/  + /'
    fi

    if [ "$rem_count" -gt 0 ]; then
        echo -e "\n${RED}✗ Will remove ($rem_count):${NC}"
        echo "$removals" | grep -v '^$' | sed 's/^/  - /'
    fi

    echo -e "\n${BLUE}Unchanged: $unc_count packages${NC}"
}

# Main diff function
show_diff() {
    local hostname=$(get_hostname)

    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  nix-me Package Diff - $hostname${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    # Fetch latest changes
    fetch_latest

    # Get current packages
    echo -e "\n${YELLOW}Analyzing current installation...${NC}"
    local current_brews=$(get_current_brews)
    local current_casks=$(get_current_casks)
    local current_nix=$(get_current_nix_packages)

    # Determine configuration file location
    local config_file=""
    if [ -f "$REPO_DIR/hosts/machines/$hostname/default.nix" ]; then
        config_file="$REPO_DIR/hosts/machines/$hostname/default.nix"
    else
        # Try to determine from flake
        local machine_type=$(grep -A 10 "\"$hostname\"" "$REPO_DIR/flake.nix" | grep "machineType" | cut -d'"' -f2)
        if [ -n "$machine_type" ] && [ -f "$REPO_DIR/hosts/types/$machine_type/default.nix" ]; then
            config_file="$REPO_DIR/hosts/types/$machine_type/default.nix"
        fi
    fi

    if [ -z "$config_file" ]; then
        echo -e "${RED}Error: Could not find configuration for $hostname${NC}"
        exit 1
    fi

    echo -e "${YELLOW}Reading configuration from: $config_file${NC}"

    # Get new packages from config (using origin/main or current remote branch)
    local current_branch=$(git rev-parse --abbrev-ref HEAD)
    local remote_ref="origin/main"

    # Try origin/main first, fall back to current branch
    if ! git show origin/main:"${config_file#$REPO_DIR/}" > /tmp/nix-me-new-config.nix 2>/dev/null; then
        echo -e "${YELLOW}Note: Configuration not found on origin/main, using current branch${NC}"
        # Use current local version instead
        cp "$config_file" /tmp/nix-me-new-config.nix
    fi

    local new_brews=$(get_config_packages "/tmp/nix-me-new-config.nix" "brews")
    local new_casks=$(get_config_packages "/tmp/nix-me-new-config.nix" "casks")
    local new_nix=$(get_config_packages "/tmp/nix-me-new-config.nix" "systemPackages")

    # Show diffs
    compare_lists "$current_brews" "$new_brews" "Homebrew Formulas (CLI Tools)"
    compare_lists "$current_casks" "$new_casks" "Homebrew Casks (GUI Applications)"
    compare_lists "$current_nix" "$new_nix" "Nix System Packages"

    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    # Cleanup
    rm -f /tmp/nix-me-new-config.nix
}

# Interactive mode - ask to apply changes
interactive_diff() {
    show_diff

    echo ""
    echo -e "${YELLOW}Would you like to apply these changes? (y/N)${NC} "
    read -r response

    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo -e "\n${GREEN}Applying changes...${NC}"
        cd "$REPO_DIR"

        # Pull latest
        git pull origin main

        # Run switch
        if [ -f "$REPO_DIR/Makefile" ]; then
            make switch
        else
            darwin-rebuild switch --flake ".#$(get_hostname)"
        fi
    else
        echo -e "${YELLOW}Cancelled. No changes applied.${NC}"
    fi
}

# Run based on argument
case "${1:-interactive}" in
    "show")
        show_diff
        ;;
    "interactive")
        interactive_diff
        ;;
    *)
        echo "Usage: $0 [show|interactive]"
        exit 1
        ;;
esac
