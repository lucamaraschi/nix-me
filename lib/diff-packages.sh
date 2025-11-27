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

# Get current hostname for flake (lowercase to match flake.nix keys)
get_hostname() {
    local name
    if [ -f "$HOME/.config/nixpkgs/.current-hostname" ]; then
        name=$(cat "$HOME/.config/nixpkgs/.current-hostname")
    else
        name=$(scutil --get LocalHostName 2>/dev/null || hostname -s)
    fi
    # Convert to lowercase to match flake.nix convention
    echo "$name" | tr '[:upper:]' '[:lower:]'
}

# Get currently installed Homebrew formulas (CLI tools)
get_current_brews() {
    /opt/homebrew/bin/brew list --formula 2>/dev/null | sort || echo ""
}

# Get currently installed Homebrew casks (GUI apps)
get_current_casks() {
    /opt/homebrew/bin/brew list --cask 2>/dev/null | sort || echo ""
}

# Get currently installed Nix packages from system profile
get_current_nix_packages() {
    # Query the actual darwin system profile, not user nix-env
    nix-store --query --references /run/current-system/sw 2>/dev/null | \
        while read path; do basename "$path"; done | \
        sed 's/^[^-]*-//' | \
        sort -u || echo ""
}

# Build Nix expression to query actual packages
build_nix_query() {
    local hostname="$1"

    cat > /tmp/nix-me-query.nix <<EOF
let
  flake = builtins.getFlake "git+file://$REPO_DIR";
  config = flake.darwinConfigurations."$hostname".config;
in
{
  brews = config.homebrew.brews or [];
  casks = config.homebrew.casks or [];
  systemPackages = map (pkg: pkg.name or pkg.pname or "unknown") config.environment.systemPackages;
}
EOF
}

# Query packages using Nix evaluation
get_nix_evaluated_packages() {
    local hostname="$1"
    local package_type="$2"

    build_nix_query "$hostname"

    case "$package_type" in
        "brews"|"casks")
            # Homebrew packages have .name field, deduplicate
            nix eval --impure --json -f /tmp/nix-me-query.nix "$package_type" 2>/dev/null | \
                jq -r '.[].name' 2>/dev/null | \
                sort -u || echo ""
            ;;
        "systemPackages")
            # System packages are already strings, deduplicate
            nix eval --impure --json -f /tmp/nix-me-query.nix "$package_type" 2>/dev/null | \
                jq -r '.[]' 2>/dev/null | \
                sort -u || echo ""
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

    # Evaluate what packages WOULD be installed with the new config
    echo -e "${YELLOW}Evaluating new configuration from origin/main...${NC}"

    # Stash any local changes temporarily
    local had_changes=false
    if ! git diff-index --quiet HEAD --; then
        had_changes=true
        git stash push -m "nix-me-diff-temp" --quiet 2>/dev/null || true
    fi

    # Checkout origin/main temporarily to evaluate
    git fetch origin main --quiet
    local current_branch=$(git rev-parse --abbrev-ref HEAD)
    git checkout origin/main --quiet 2>/dev/null || {
        echo -e "${RED}Error: Could not checkout origin/main${NC}"
        [ "$had_changes" = true ] && git stash pop --quiet 2>/dev/null
        exit 1
    }

    # Evaluate packages using Nix
    local new_brews=$(get_nix_evaluated_packages "$hostname" "brews")
    local new_casks=$(get_nix_evaluated_packages "$hostname" "casks")
    local new_nix=$(get_nix_evaluated_packages "$hostname" "systemPackages")

    # Return to original branch
    git checkout "$current_branch" --quiet 2>/dev/null
    [ "$had_changes" = true ] && git stash pop --quiet 2>/dev/null

    # Show diffs
    compare_lists "$current_brews" "$new_brews" "Homebrew Formulas (CLI Tools)"
    compare_lists "$current_casks" "$new_casks" "Homebrew Casks (GUI Applications)"
    compare_lists "$current_nix" "$new_nix" "Nix System Packages"

    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    # Cleanup
    rm -f /tmp/nix-me-query.nix
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
