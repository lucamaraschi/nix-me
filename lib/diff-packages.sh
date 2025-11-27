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

# Get current nix-darwin generation
get_current_generation() {
    if [ -L /run/current-system ]; then
        local system_path=$(readlink /run/current-system)
        local generation=$(basename "$system_path" | sed 's/system-//')
        echo "$generation"
    else
        echo "unknown"
    fi
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

# Query packages from a specific module/file
get_packages_from_module() {
    local hostname="$1"
    local module_path="$2"
    local package_type="$3"

    # Create a Nix expression to evaluate just this module's packages
    cat > /tmp/nix-me-module-query.nix <<EOF
let
  flake = builtins.getFlake "git+file://$REPO_DIR";
  pkgs = flake.inputs.nixpkgs.legacyPackages.aarch64-darwin;

  # Import the module
  moduleImport = import $module_path;

  # Evaluate the module
  module = if builtins.isFunction moduleImport
           then moduleImport { inherit pkgs; }
           else moduleImport;

  # Extract packages based on type
  result =
    if "$package_type" == "brews" then
      (module.homebrew.brews or [])
    else if "$package_type" == "casks" then
      (module.homebrew.casks or [])
    else if "$package_type" == "nix" then
      (module.environment.systemPackages or [])
    else [];
in
  if "$package_type" == "nix" then
    map (pkg: pkg.name or pkg.pname or "unknown") result
  else
    map (item: item.name or item) result
EOF

    nix eval --impure --json -f /tmp/nix-me-module-query.nix 2>/dev/null | jq -r '.[]' 2>/dev/null | sort -u || echo ""
    rm -f /tmp/nix-me-module-query.nix
}

# Build package source map (pre-compute for performance)
build_package_source_map() {
    local hostname="$1"
    local package_type="$2"

    declare -gA PACKAGE_SOURCE_MAP

    local shared_packages_path="$REPO_DIR/modules/shared/packages.nix"
    local darwin_modules_path="$REPO_DIR/modules/darwin"
    local host_path="$REPO_DIR/hosts/$hostname/default.nix"

    # Build map based on package type (only for nix packages)
    if [[ "$package_type" == "nix" ]]; then
        # Extract packages from shared
        if [[ -f "$shared_packages_path" ]]; then
            while IFS= read -r pkg; do
                [[ -n "$pkg" ]] && PACKAGE_SOURCE_MAP["$pkg"]="${PACKAGE_SOURCE_MAP[$pkg]:+${PACKAGE_SOURCE_MAP[$pkg]},}shared"
            done < <(grep "pkgs\." "$shared_packages_path" 2>/dev/null | sed -n 's/.*pkgs\.\([a-zA-Z0-9_-]*\).*/\1/p')
        fi

        # Extract packages from darwin modules
        if [[ -d "$darwin_modules_path" ]]; then
            while IFS= read -r pkg; do
                [[ -n "$pkg" ]] && PACKAGE_SOURCE_MAP["$pkg"]="${PACKAGE_SOURCE_MAP[$pkg]:+${PACKAGE_SOURCE_MAP[$pkg]},}darwin"
            done < <(grep -r "pkgs\." "$darwin_modules_path" 2>/dev/null | sed -n 's/.*pkgs\.\([a-zA-Z0-9_-]*\).*/\1/p' | sort -u)
        fi
    fi
}

# Detect which config layers contribute a package
detect_package_sources() {
    local hostname="$1"
    local package="$2"
    local package_type="$3"

    # Strip version from package name (e.g., "jq-1.8.1" -> "jq")
    local package_name=$(echo "$package" | sed 's/-[0-9].*//')

    # Look up in pre-built map
    echo "${PACKAGE_SOURCE_MAP[$package_name]}"
}

# Extract package name without version
get_pkg_name() {
    echo "$1" | awk '{print $1}'
}

# Extract version
get_pkg_version() {
    echo "$1" | awk '{print $2}'
}

# Check and prompt for flake input updates (returns 0 if updated, 1 if not)
check_and_update_flake() {
    echo -e "${YELLOW}→${NC} Checking for flake input updates..."
    cd "$REPO_DIR"

    # Get current nixpkgs revision
    local current_rev=$(nix flake metadata --json 2>/dev/null | jq -r '.locks.nodes.nixpkgs.locked.rev' 2>/dev/null | cut -c1-7)

    # Get latest nixpkgs revision
    local latest_rev=$(nix flake metadata github:NixOS/nixpkgs/nixpkgs-unstable --json 2>/dev/null | jq -r '.revision' 2>/dev/null | cut -c1-7)

    if [[ -n "$current_rev" && -n "$latest_rev" && "$current_rev" != "$latest_rev" ]]; then
        echo -e "${BOLD}${MAGENTA}╔═══════════════════════════════════════════════════════════╗${NC}"
        echo -e "${BOLD}${MAGENTA}║  📦 Flake Input Updates Available                         ║${NC}"
        echo -e "${BOLD}${MAGENTA}╚═══════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "  ${YELLOW}${BOLD}↑ nixpkgs${NC}"
        echo -e "    ${DIM}Current: $current_rev${NC}"
        echo -e "    ${DIM}Latest:  $latest_rev${NC}"
        echo ""
        echo -e "${BOLD}${YELLOW}Update flake inputs now?${NC} ${DIM}(y/N)${NC} "
        read -r response

        if [[ "$response" =~ ^[Yy]$ ]]; then
            echo ""
            echo -e "${GREEN}→${NC} Updating flake inputs..."
            nix flake update
            echo -e "${GREEN}✓${NC} ${DIM}Flake inputs updated${NC}"
            echo ""
            return 0
        else
            echo -e "${YELLOW}→${NC} ${DIM}Skipping flake update${NC}"
            echo ""
        fi
    fi
    return 1
}

# Check and prompt for Homebrew package upgrades (returns 0 if upgraded, 1 if not)
check_and_upgrade_brew() {
    echo -e "${YELLOW}→${NC} Checking for Homebrew upgrades..."

    # Get outdated formulas
    local outdated_brews=$(/opt/homebrew/bin/brew outdated --formula --quiet 2>/dev/null | sort)
    local outdated_casks=$(/opt/homebrew/bin/brew outdated --cask --greedy --quiet 2>/dev/null | sort)

    local brew_count=$(echo "$outdated_brews" | grep -v '^$' | wc -l | tr -d ' ')
    local cask_count=$(echo "$outdated_casks" | grep -v '^$' | wc -l | tr -d ' ')

    if [[ "$brew_count" -gt 0 || "$cask_count" -gt 0 ]]; then
        echo -e "${BOLD}${MAGENTA}╔═══════════════════════════════════════════════════════════╗${NC}"
        echo -e "${BOLD}${MAGENTA}║  ⚡ Homebrew Upgrades Available                           ║${NC}"
        echo -e "${BOLD}${MAGENTA}╚═══════════════════════════════════════════════════════════╝${NC}"
        echo ""

        if [[ "$brew_count" -gt 0 ]]; then
            echo -e "  ${YELLOW}${BOLD}↑ Formulas ($brew_count):${NC}"
            echo "$outdated_brews" | grep -v '^$' | while read pkg; do
                local current_ver=$(/opt/homebrew/bin/brew list --versions "$pkg" 2>/dev/null | awk '{print $2}')
                local latest_ver=$(/opt/homebrew/bin/brew info --json=v2 "$pkg" 2>/dev/null | jq -r '.formulae[0].versions.stable' 2>/dev/null)
                echo -e "    ${YELLOW}↑${NC} $pkg ${DIM}($current_ver → $latest_ver)${NC}"
            done
            echo ""
        fi

        if [[ "$cask_count" -gt 0 ]]; then
            echo -e "  ${YELLOW}${BOLD}↑ Casks ($cask_count):${NC}"
            echo "$outdated_casks" | grep -v '^$' | while read pkg; do
                local current_ver=$(/opt/homebrew/bin/brew list --cask --versions "$pkg" 2>/dev/null | awk '{print $2}')
                local latest_ver=$(/opt/homebrew/bin/brew info --cask --json=v2 "$pkg" 2>/dev/null | jq -r '.casks[0].version' 2>/dev/null)
                echo -e "    ${YELLOW}↑${NC} $pkg ${DIM}($current_ver → $latest_ver)${NC}"
            done
            echo ""
        fi

        echo -e "${BOLD}${YELLOW}Upgrade Homebrew packages now?${NC} ${DIM}(y/N)${NC} "
        read -r response

        if [[ "$response" =~ ^[Yy]$ ]]; then
            echo ""
            echo -e "${GREEN}→${NC} Upgrading Homebrew packages..."
            /opt/homebrew/bin/brew upgrade
            echo -e "${GREEN}✓${NC} ${DIM}Homebrew packages upgraded${NC}"
            echo ""
            return 0
        else
            echo -e "${YELLOW}→${NC} ${DIM}Skipping Homebrew upgrade${NC}"
            echo ""
        fi
    fi
    return 1
}

# Compare versions and detect upgrades
compare_packages() {
    local current_list="$1"
    local new_list="$2"
    local label="$3"
    local show_versions="$4"  # true/false
    local hostname="$5"
    local package_type="$6"  # "brews", "casks", or "nix"

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
            local source=$(detect_package_sources "$hostname" "$pkg" "$package_type")
            if [[ -n "$source" ]]; then
                echo -e "    ${GREEN}+${NC} $pkg ${DIM}[$source]${NC}"
            else
                echo -e "    ${GREEN}+${NC} $pkg"
            fi
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
            local source=$(detect_package_sources "$hostname" "$pkg" "$package_type")
            if [[ -n "$source" ]]; then
                echo -e "    ${RED}-${NC} $pkg ${DIM}[$source]${NC}"
            else
                echo -e "    ${RED}-${NC} $pkg"
            fi
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
    local generation=$(get_current_generation)

    # Header
    clear
    echo -e "${BOLD}${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${BLUE}║                  nix-me Package Diff                      ║${NC}"
    echo -e "${BOLD}${BLUE}║                  $hostname${NC}"
    echo -e "${BOLD}${BLUE}║                  ${DIM}Generation: $generation${NC}"
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

    # Build package source map for faster lookups
    build_package_source_map "$hostname" "nix"

    # Show diffs
    compare_packages "$current_brews" "$new_brews" "🍺 Homebrew Formulas (CLI Tools)" "true" "$hostname" "brews"
    compare_packages "$current_casks" "$new_casks" "📦 Homebrew Casks (GUI Apps)" "true" "$hostname" "casks"
    compare_packages "$current_nix" "$new_nix" "❄️  Nix System Packages" "false" "$hostname" "nix"

    # Summary footer
    echo ""
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo ""

    # Cleanup
    rm -f /tmp/nix-me-query.nix
}

# Interactive mode
interactive_diff() {
    local hostname=$(get_hostname)
    local generation=$(get_current_generation)

    # Header
    clear
    echo -e "${BOLD}${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${BLUE}║                  nix-me Package Diff                      ║${NC}"
    echo -e "${BOLD}${BLUE}║                  $hostname${NC}"
    echo -e "${BOLD}${BLUE}║                  ${DIM}Generation: $generation${NC}"
    echo -e "${BOLD}${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Step 1: Check and offer to update flake inputs
    check_and_update_flake
    local flake_updated=$?

    # Step 2: Check and offer to upgrade Homebrew packages
    check_and_upgrade_brew
    local brew_upgraded=$?

    # Step 3: Show the diff (now reflects updated state)
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

    # Build package source map for faster lookups
    build_package_source_map "$hostname" "nix"

    # Show diffs
    compare_packages "$current_brews" "$new_brews" "🍺 Homebrew Formulas (CLI Tools)" "true" "$hostname" "brews"
    compare_packages "$current_casks" "$new_casks" "📦 Homebrew Casks (GUI Apps)" "true" "$hostname" "casks"
    compare_packages "$current_nix" "$new_nix" "❄️  Nix System Packages" "false" "$hostname" "nix"

    # Summary footer
    echo ""
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo ""

    # Step 4: Prompt to apply configuration changes
    echo -e "${BOLD}${YELLOW}Apply these configuration changes?${NC} ${DIM}(y/N)${NC} "
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

    # Cleanup
    rm -f /tmp/nix-me-query.nix
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
