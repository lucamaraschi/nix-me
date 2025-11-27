#!/usr/bin/env bash

# Package diff utility for nix-me (Enhanced Version)
# Shows what will be added/removed/upgraded before switching

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Enhanced Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Get current hostname
get_hostname() {
    local name
    if [ -f "$HOME/.config/nixpkgs/.current-hostname" ]; then
        name=$(cat "$HOME/.config/nixpkgs/.current-hostname")
    else
        name=$(scutil --get LocalHostName 2>/dev/null || hostname -s)
    fi
    echo "$name" | tr '[:upper:]' '[:lower:]'
}

# Get currently installed packages with versions
get_current_brews() {
    /opt/homebrew/bin/brew list --formula --versions 2>/dev/null | sort || echo ""
}

get_current_casks() {
    /opt/homebrew/bin/brew list --cask --versions 2>/dev/null | sort || echo ""
}

get_current_nix_packages() {
    nix-store --query --references /run/current-system/sw 2>/dev/null | \
        while read path; do basename "$path"; done | \
        sed 's/^[^-]*-//' | \
        grep -vE -- '-(man|info|doc|dev|bin|out|lib|debug|dnsutils)$' | \
        sort -u || echo ""
}

# Build Nix query
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

# Query packages from Nix evaluation
get_nix_evaluated_packages() {
    local hostname="$1"
    local package_type="$2"
    build_nix_query "$hostname"
    case "$package_type" in
        "brews"|"casks")
            nix eval --impure --json -f /tmp/nix-me-query.nix "$package_type" 2>/dev/null | \
                jq -r '.[].name' 2>/dev/null | sort -u || echo ""
            ;;
        "systemPackages")
            nix eval --impure --json -f /tmp/nix-me-query.nix "$package_type" 2>/dev/null | \
                jq -r '.[]' 2>/dev/null | sort -u || echo ""
            ;;
    esac
}

# Extract package name without version
get_pkg_name() {
    echo "$1" | awk '{print $1}'
}

# Extract version
get_pkg_version() {
    echo "$1" | awk '{print $2}'
}

# Compare versions and detect upgrades
compare_packages() {
    local current_list="$1"
    local new_list="$2"
    local label="$3"
    local show_versions="$4"  # true/false

    declare -A current_packages new_packages

    # Parse current packages
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local name=$(get_pkg_name "$line")
        local version=$(get_pkg_version "$line")
        current_packages["$name"]="$version"
    done <<< "$current_list"

    # Parse new packages
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        new_packages["$line"]="1"
    done <<< "$new_list"

    # Find additions, removals, upgrades
    local -a additions removals upgrades unchanged

    # Check for additions and upgrades
    for pkg in "${!new_packages[@]}"; do
        if [[ ! -v current_packages[$pkg] ]]; then
            additions+=("$pkg")
        else
            if [[ -n "${current_packages[$pkg]}" && "$show_versions" == "true" ]]; then
                # For now, assume it's unchanged; real version comparison would need brew info
                unchanged+=("$pkg")
            else
                unchanged+=("$pkg")
            fi
        fi
    done

    # Check for removals
    for pkg in "${!current_packages[@]}"; do
        if [[ ! -v new_packages[$pkg] ]]; then
            removals+=("$pkg")
        fi
    done

    # Display results
    echo ""
    echo -e "${BOLD}${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║  $label${NC}"
    echo -e "${BOLD}${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"

    local total_changes=$((${#additions[@]} + ${#removals[@]} + ${#upgrades[@]}))

    if [[ $total_changes -eq 0 ]]; then
        echo -e "  ${DIM}No changes - ${#unchanged[@]} packages unchanged${NC}"
        return
    fi

    # Show additions
    if [[ ${#additions[@]} -gt 0 ]]; then
        echo -e "\n  ${GREEN}${BOLD}✓ Will Install (${#additions[@]}):${NC}"
        for pkg in "${additions[@]}"; do
            echo -e "    ${GREEN}+${NC} $pkg"
        done
    fi

    # Show upgrades
    if [[ ${#upgrades[@]} -gt 0 ]]; then
        echo -e "\n  ${YELLOW}${BOLD}↑ Will Upgrade (${#upgrades[@]}):${NC}"
        for pkg in "${upgrades[@]}"; do
            echo -e "    ${YELLOW}↑${NC} $pkg"
        done
    fi

    # Show removals
    if [[ ${#removals[@]} -gt 0 ]]; then
        echo -e "\n  ${RED}${BOLD}✗ Will Remove (${#removals[@]}):${NC}"
        for pkg in "${removals[@]}"; do
            echo -e "    ${RED}-${NC} $pkg"
        done
    fi

    # Show summary
    if [[ ${#unchanged[@]} -gt 0 ]]; then
        echo -e "\n  ${DIM}→ Unchanged: ${#unchanged[@]} packages${NC}"
    fi
}

# Main diff function
show_diff() {
    local hostname=$(get_hostname)

    # Header
    clear
    echo -e "${BOLD}${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${BLUE}║                  nix-me Package Diff                      ║${NC}"
    echo -e "${BOLD}${BLUE}║                  $hostname${NC}"
    echo -e "${BOLD}${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Fetch latest
    echo -e "${YELLOW}→${NC} Fetching latest from GitHub..."
    cd "$REPO_DIR"
    git fetch origin main --quiet 2>/dev/null || true
    echo -e "${GREEN}✓${NC} ${DIM}Fetched latest changes${NC}"

    # Get current state
    echo -e "${YELLOW}→${NC} Analyzing current installation..."
    local current_brews=$(get_current_brews)
    local current_casks=$(get_current_casks)
    local current_nix=$(get_current_nix_packages)

    # Evaluate new config
    echo -e "${YELLOW}→${NC} Evaluating new configuration..."

    # Stash changes
    local had_changes=false
    if ! git diff-index --quiet HEAD -- 2>/dev/null; then
        had_changes=true
        git stash push -m "nix-me-diff-temp" --quiet 2>/dev/null || true
    fi

    # Checkout origin/main
    local current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    git checkout origin/main --quiet 2>/dev/null || {
        echo -e "${RED}Error: Could not checkout origin/main${NC}"
        [[ "$had_changes" = true ]] && git stash pop --quiet 2>/dev/null
        exit 1
    }

    # Evaluate packages
    local new_brews=$(get_nix_evaluated_packages "$hostname" "brews")
    local new_casks=$(get_nix_evaluated_packages "$hostname" "casks")
    local new_nix=$(get_nix_evaluated_packages "$hostname" "systemPackages")

    # Return to original branch
    git checkout "$current_branch" --quiet 2>/dev/null
    [[ "$had_changes" = true ]] && git stash pop --quiet 2>/dev/null

    echo -e "${GREEN}✓${NC} ${DIM}Analysis complete${NC}"

    # Show diffs
    compare_packages "$current_brews" "$new_brews" "🍺 Homebrew Formulas (CLI Tools)" "true"
    compare_packages "$current_casks" "$new_casks" "📦 Homebrew Casks (GUI Apps)" "true"
    compare_packages "$current_nix" "$new_nix" "❄️  Nix System Packages" "false"

    # Summary footer
    echo ""
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo ""

    # Cleanup
    rm -f /tmp/nix-me-query.nix
}

# Interactive mode
interactive_diff() {
    show_diff

    echo ""
    echo -e "${BOLD}${YELLOW}Apply these changes?${NC} ${DIM}(y/N)${NC} "
    read -r response

    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo ""
        echo -e "${GREEN}→${NC} Pulling latest changes..."
        cd "$REPO_DIR"
        git pull origin main --quiet

        echo -e "${GREEN}→${NC} Applying configuration..."
        if [[ -f "$REPO_DIR/Makefile" ]]; then
            make switch
        else
            darwin-rebuild switch --flake ".#$(get_hostname)"
        fi
    else
        echo -e "${YELLOW}✗${NC} ${DIM}Cancelled - no changes applied${NC}"
    fi
}

# Run
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
