#!/usr/bin/env bash
# lib/tui.sh - Main TUI menu and configuration inspector
# Provides a polished interactive interface for nix-me

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/ui.sh"

# Detect CONFIG_DIR - prefer current project if running from nix-me repo
if [[ -f "$(dirname "$SCRIPT_DIR")/flake.nix" ]]; then
    CONFIG_DIR="$(cd "$(dirname "$SCRIPT_DIR")" && pwd)"
elif [[ -d "${HOME}/.config/nixpkgs" ]]; then
    CONFIG_DIR="${HOME}/.config/nixpkgs"
else
    CONFIG_DIR="${HOME}/.config/nixpkgs"  # Default even if doesn't exist
fi

# ============================================================================
# Installation Detection
# ============================================================================

is_nix_me_installed() {
    # Check if nix-darwin is installed and config exists
    if command -v darwin-rebuild &>/dev/null && [[ -d "$CONFIG_DIR" ]] && [[ -f "$CONFIG_DIR/flake.nix" ]]; then
        return 0
    fi
    return 1
}

# ============================================================================
# Main Menu
# ============================================================================

main_menu() {
    # First-run detection
    if ! is_nix_me_installed; then
        show_welcome_screen
        return $?
    fi

    # Main dashboard loop
    while true; do
        show_dashboard

        read -p "$(echo -e "\n  ${CYAN}Action${NC} [press key]: ")" choice

        case "$choice" in
            1) menu_browse_apps ;;
            2) menu_update_all ;;
            3) menu_apply_changes ;;
            r) menu_rollback ;;
            v) menu_vm_management ;;
            i) inspector_main ;;
            s) show_full_system_status ;;
            c) menu_reconfigure ;;
            h) show_help_menu ;;
            q|Q)
                clear
                echo ""
                echo -e "  ${GREEN}✨ Happy hacking!${NC}"
                echo ""
                exit 0
                ;;
            "")
                # Refresh dashboard
                ;;
            *)
                ;;
        esac
    done
}

# ============================================================================
# Welcome Screen (First Run)
# ============================================================================

show_welcome_screen() {
    clear
    echo ""
    echo "  Welcome to nix-me"
    echo ""
    echo "  Declarative macOS Configuration Manager"
    echo ""
    echo "  nix-me isn't installed yet."
    echo ""
    echo "  What this does:"
    echo "    • Manage system packages declaratively"
    echo "    • Install apps via Homebrew"
    echo "    • Reproducible environments"
    echo "    • Easy rollbacks"
    echo ""
    echo -e "  ${GREEN}1${NC} Install nix-me (guided setup)"
    echo -e "  ${GREEN}2${NC} Exit"
    echo ""

    read -p "  Choose [1]: " choice
    choice=${choice:-1}

    case "$choice" in
        1)
            if type run_configuration_wizard &>/dev/null; then
                run_configuration_wizard
            else
                echo ""
                echo "  Configuration wizard not available"
                echo "  Run: ./install.sh"
                echo ""
                sleep 3
            fi
            ;;
        2|q|Q)
            clear
            return 0
            ;;
    esac
}

# ============================================================================
# Dashboard (Installed)
# ============================================================================

show_dashboard() {
    clear

    local hostname=$(hostname -s 2>/dev/null | tr '[:upper:]' '[:lower:]')
    local branch=$(cd "$CONFIG_DIR" 2>/dev/null && git branch --show-current 2>/dev/null || echo "main")
    local nix_gen=$(darwin-rebuild --list-generations 2>/dev/null | tail -1 | awk '{print $1}' || echo "?")
    local uncommitted=$(cd "$CONFIG_DIR" 2>/dev/null && git status --porcelain 2>/dev/null | wc -l | tr -d ' ')

    # Package counts
    local brew_casks=$(brew list --cask 2>/dev/null | wc -l | tr -d ' ')
    local brew_formulas=$(brew list --formula 2>/dev/null | wc -l | tr -d ' ')
    local nix_pkgs=$(ls /run/current-system/sw/bin 2>/dev/null | wc -l | tr -d ' ')

    # Updates available
    local brew_updates=$(brew outdated 2>/dev/null | wc -l | tr -d ' ')

    echo ""
    echo "  nix-me"
    echo ""
    echo "  ${hostname} • gen ${nix_gen} • ${branch}"
    if [[ $uncommitted -gt 0 ]]; then
        echo -e "  ${YELLOW}${uncommitted} uncommitted changes${NC}"
    fi
    echo ""

    echo "  Packages"
    echo "    ${brew_casks} GUI apps"
    echo "    ${brew_formulas} CLI tools (brew)"
    echo "    ${nix_pkgs} CLI tools (nix)"

    if [[ $brew_updates -gt 0 ]]; then
        echo ""
        echo "  Updates"
        echo -e "    ${YELLOW}${brew_updates} packages available${NC}"
    fi

    echo ""
    echo -e "  ${GREEN}1${NC} Browse apps    ${GREEN}2${NC} Update all    ${GREEN}3${NC} Apply changes"
    echo ""
    echo -e "  ${GREEN}v${NC} VMs    ${GREEN}i${NC} Inspector    ${GREEN}s${NC} System    ${GREEN}r${NC} Rollback"
    echo ""
    echo -e "  ${GREEN}h${NC} Help    ${GREEN}q${NC} Quit    ${GREEN}Enter${NC} Refresh"
    echo ""
}

# ============================================================================
# Configuration Inspector
# ============================================================================

show_full_system_status() {
    if type cmd_doctor &>/dev/null; then
        clear
        cmd_doctor
        echo ""
        echo -e "  ${GREEN}[Enter]${NC} Back"
        read -p "" dummy
    else
        inspector_dashboard
    fi
}

inspector_main() {
    while true; do
        clear
        echo ""
        echo "  Inspector"
        echo ""
        echo -e "  ${GREEN}1${NC} Overview dashboard"
        echo -e "  ${GREEN}2${NC} Installed apps (Homebrew)"
        echo -e "  ${GREEN}3${NC} System packages (Nix)"
        echo -e "  ${GREEN}4${NC} Configuration files"
        echo -e "  ${GREEN}5${NC} Recent changes (Git)"
        echo -e "  ${GREEN}6${NC} Pending updates"
        echo ""
        echo -e "  ${GREEN}0${NC} Back"
        echo ""

        read -p "  Choose [0]: " choice
        choice=${choice:-0}

        case "$choice" in
            1) inspector_dashboard ;;
            2) inspector_homebrew_apps ;;
            3) inspector_nix_packages ;;
            4) inspector_config_files ;;
            5) inspector_git_changes ;;
            6) inspector_pending_updates ;;
            0|q|Q|"") return 0 ;;
        esac
    done
}

inspector_dashboard() {
    clear
    print_header "Configuration Dashboard"
    echo ""

    local hostname=$(hostname -s 2>/dev/null | tr '[:upper:]' '[:lower:]')

    # System Info
    echo -e "  ${CYAN}System${NC}"
    echo -e "  ├─ Hostname: ${GREEN}$hostname${NC}"
    echo -e "  ├─ macOS: $(sw_vers -productVersion 2>/dev/null || echo 'unknown')"
    echo -e "  ├─ Chip: $(sysctl -n machdep.cpu.brand_string 2>/dev/null | head -1 || echo 'unknown')"
    echo -e "  └─ RAM: $(($(sysctl -n hw.memsize 2>/dev/null) / 1024 / 1024 / 1024))GB"
    echo ""

    # Nix Info
    echo -e "  ${CYAN}Nix${NC}"
    local nix_version=$(nix --version 2>/dev/null | head -1 || echo 'not installed')
    local nix_gen=$(darwin-rebuild --list-generations 2>/dev/null | tail -1 | awk '{print $1}' || echo '?')
    local nix_store_size=$(du -sh /nix/store 2>/dev/null | cut -f1 || echo 'unknown')
    echo -e "  ├─ Version: ${GREEN}$nix_version${NC}"
    echo -e "  ├─ Generation: ${GREEN}$nix_gen${NC}"
    echo -e "  └─ Store Size: ${YELLOW}$nix_store_size${NC}"
    echo ""

    # Configuration
    echo -e "  ${CYAN}Configuration${NC}"
    if [[ -d "$CONFIG_DIR" ]]; then
        local branch=$(cd "$CONFIG_DIR" && git branch --show-current 2>/dev/null || echo 'unknown')
        local last_commit=$(cd "$CONFIG_DIR" && git log -1 --format="%h %s" 2>/dev/null | head -c 60 || echo 'unknown')
        local uncommitted=$(cd "$CONFIG_DIR" && git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
        echo -e "  ├─ Location: ${GREEN}$CONFIG_DIR${NC}"
        echo -e "  ├─ Branch: ${GREEN}$branch${NC}"
        echo -e "  ├─ Last: ${CYAN}$last_commit${NC}"
        if [[ $uncommitted -gt 0 ]]; then
            echo -e "  └─ Uncommitted: ${YELLOW}$uncommitted changes${NC}"
        else
            echo -e "  └─ Status: ${GREEN}Clean${NC}"
        fi
    else
        echo -e "  └─ ${RED}Not found${NC}"
    fi
    echo ""

    # Package Counts
    echo -e "  ${CYAN}Packages${NC}"
    local brew_casks=$(brew list --cask 2>/dev/null | wc -l | tr -d ' ')
    local brew_formulas=$(brew list --formula 2>/dev/null | wc -l | tr -d ' ')
    local nix_pkgs=$(ls /run/current-system/sw/bin 2>/dev/null | wc -l | tr -d ' ')
    echo -e "  ├─ Homebrew Casks: ${GREEN}$brew_casks${NC}"
    echo -e "  ├─ Homebrew Formulas: ${GREEN}$brew_formulas${NC}"
    echo -e "  └─ Nix System Packages: ${GREEN}$nix_pkgs${NC}"
    echo ""

    # Quick Actions
    echo -e "  ${CYAN}Quick Actions${NC}"
    echo -e "  [u] Update all    [s] Switch    [c] Clean store    [b] Back"
    echo ""

    read -p "$(echo -e ${CYAN}Action${NC} [b]: )" action
    action=${action:-b}

    case "$action" in
        u) menu_update_all ;;
        s) menu_apply_changes ;;
        c) clean_nix_store ;;
        b) return 0 ;;
    esac
}

inspector_homebrew_apps() {
    clear
    print_header "Installed Applications (Homebrew Casks)"
    echo ""

    if ! command -v brew &>/dev/null; then
        print_error "Homebrew not installed"
        read -p "Press Enter to continue..."
        return 1
    fi

    local casks=$(brew list --cask 2>/dev/null | sort)
    local count=$(echo "$casks" | wc -l | tr -d ' ')

    echo -e "  Total: ${GREEN}$count${NC} applications"
    echo ""

    if command -v fzf &>/dev/null; then
        echo "$casks" | while read cask; do
            echo -e "  ${GREEN}✓${NC} $cask"
        done | fzf --height=70% \
                   --border=rounded \
                   --header="Installed Homebrew Casks | Press Enter to view details, ESC to go back" \
                   --preview="brew info --cask {2} 2>/dev/null | head -20" \
                   --preview-window=right:50%:wrap \
                   --ansi || true
    else
        echo "$casks" | while read cask; do
            echo -e "  ${GREEN}✓${NC} $cask"
        done | head -30
        echo ""
        if [[ $count -gt 30 ]]; then
            echo -e "  ${YELLOW}... and $((count - 30)) more${NC}"
        fi
    fi

    echo ""
    read -p "Press Enter to continue..."
}

inspector_nix_packages() {
    clear
    print_header "System Packages (Nix)"
    echo ""

    local pkgs_dir="/run/current-system/sw/bin"
    if [[ ! -d "$pkgs_dir" ]]; then
        print_error "Nix system packages not found"
        read -p "Press Enter to continue..."
        return 1
    fi

    local pkgs=$(ls "$pkgs_dir" 2>/dev/null | sort)
    local count=$(echo "$pkgs" | wc -l | tr -d ' ')

    echo -e "  Total: ${GREEN}$count${NC} binaries in system path"
    echo ""

    if command -v fzf &>/dev/null; then
        echo "$pkgs" | while read pkg; do
            local version=$("$pkgs_dir/$pkg" --version 2>/dev/null | head -1 || echo "")
            if [[ -n "$version" ]]; then
                echo -e "  ${GREEN}✓${NC} $pkg  ${CYAN}$version${NC}"
            else
                echo -e "  ${GREEN}✓${NC} $pkg"
            fi
        done | fzf --height=70% \
                   --border=rounded \
                   --header="Nix System Packages | ESC to go back" \
                   --ansi || true
    else
        echo "$pkgs" | head -30 | while read pkg; do
            echo -e "  ${GREEN}✓${NC} $pkg"
        done
        echo ""
        if [[ $count -gt 30 ]]; then
            echo -e "  ${YELLOW}... and $((count - 30)) more${NC}"
        fi
    fi

    echo ""
    read -p "Press Enter to continue..."
}

inspector_config_files() {
    clear
    print_header "Configuration Files"
    echo ""

    if [[ ! -d "$CONFIG_DIR" ]]; then
        print_error "Configuration directory not found"
        read -p "Press Enter to continue..."
        return 1
    fi

    echo -e "  ${CYAN}Configuration Structure${NC}"
    echo ""

    # Show tree structure
    if command -v tree &>/dev/null; then
        tree -L 2 -d "$CONFIG_DIR" 2>/dev/null | head -30
    else
        ls -la "$CONFIG_DIR" | head -20
    fi

    echo ""
    echo -e "  ${CYAN}Key Files${NC}"
    echo -e "  ├─ flake.nix - ${GREEN}Main configuration${NC}"
    echo -e "  ├─ hosts/ - ${GREEN}Machine-specific configs${NC}"
    echo -e "  ├─ modules/ - ${GREEN}Reusable modules${NC}"
    echo -e "  └─ Makefile - ${GREEN}Build commands${NC}"
    echo ""

    if command -v fzf &>/dev/null; then
        echo -e "  ${CYAN}Quick Edit${NC} (select file to view)"
        local file=$(find "$CONFIG_DIR" -type f -name "*.nix" 2>/dev/null | \
            sed "s|$CONFIG_DIR/||" | \
            fzf --height=50% \
                --border=rounded \
                --header="Select .nix file to view" \
                --preview="head -50 $CONFIG_DIR/{}" \
                --preview-window=right:60%:wrap || echo "")

        if [[ -n "$file" ]]; then
            ${EDITOR:-less} "$CONFIG_DIR/$file"
        fi
    fi

    read -p "Press Enter to continue..."
}

inspector_git_changes() {
    clear
    print_header "Recent Changes"
    echo ""

    if [[ ! -d "$CONFIG_DIR/.git" ]]; then
        print_error "Not a git repository"
        read -p "Press Enter to continue..."
        return 1
    fi

    cd "$CONFIG_DIR"

    echo -e "  ${CYAN}Uncommitted Changes${NC}"
    local changes=$(git status --porcelain 2>/dev/null)
    if [[ -n "$changes" ]]; then
        echo "$changes" | head -10 | while read line; do
            local status="${line:0:2}"
            local file="${line:3}"
            case "$status" in
                "M "*|" M") echo -e "  ${YELLOW}Modified${NC}: $file" ;;
                "A "*) echo -e "  ${GREEN}Added${NC}: $file" ;;
                "D "*|" D") echo -e "  ${RED}Deleted${NC}: $file" ;;
                "??") echo -e "  ${CYAN}Untracked${NC}: $file" ;;
                *) echo -e "  $status: $file" ;;
            esac
        done
        local total=$(echo "$changes" | wc -l | tr -d ' ')
        if [[ $total -gt 10 ]]; then
            echo -e "  ${YELLOW}... and $((total - 10)) more${NC}"
        fi
    else
        echo -e "  ${GREEN}No uncommitted changes${NC}"
    fi
    echo ""

    echo -e "  ${CYAN}Recent Commits${NC}"
    git log --oneline --decorate -10 2>/dev/null | while read line; do
        echo -e "  ${GREEN}•${NC} $line"
    done
    echo ""

    if ask_yes_no "View full diff?" "n"; then
        git diff --stat HEAD
        echo ""
        read -p "Press Enter to continue..."
    fi
}

inspector_pending_updates() {
    clear
    print_header "Pending Updates"
    echo ""

    echo -e "  ${CYAN}Checking for updates...${NC}"
    echo ""

    # Check Homebrew
    print_step "1/3" "Homebrew Updates"
    if command -v brew &>/dev/null; then
        local outdated=$(brew outdated 2>/dev/null)
        if [[ -n "$outdated" ]]; then
            local count=$(echo "$outdated" | wc -l | tr -d ' ')
            echo -e "  ${YELLOW}$count package(s) can be updated:${NC}"
            echo "$outdated" | head -10 | while read pkg; do
                echo -e "    ${YELLOW}↑${NC} $pkg"
            done
            if [[ $(echo "$outdated" | wc -l) -gt 10 ]]; then
                echo -e "    ${YELLOW}... and more${NC}"
            fi
        else
            echo -e "  ${GREEN}All packages up to date${NC}"
        fi
    else
        print_warn "Homebrew not installed"
    fi
    echo ""

    # Check Nix flake
    print_step "2/3" "Nix Flake Inputs"
    if [[ -f "$CONFIG_DIR/flake.lock" ]]; then
        local last_update=$(stat -f "%Sm" -t "%Y-%m-%d" "$CONFIG_DIR/flake.lock" 2>/dev/null || echo "unknown")
        echo -e "  Last updated: ${CYAN}$last_update${NC}"
        echo -e "  Run ${GREEN}nix-me update${NC} to update flake inputs"
    else
        print_warn "No flake.lock found"
    fi
    echo ""

    # Check if rebuild needed
    print_step "3/3" "Configuration Status"
    if [[ -d "$CONFIG_DIR/.git" ]]; then
        cd "$CONFIG_DIR"
        local uncommitted=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
        if [[ $uncommitted -gt 0 ]]; then
            echo -e "  ${YELLOW}$uncommitted uncommitted changes${NC}"
            echo -e "  Run ${GREEN}nix-me switch${NC} to apply changes"
        else
            echo -e "  ${GREEN}Configuration is in sync${NC}"
        fi
    fi
    echo ""

    if ask_yes_no "Update all now?" "n"; then
        menu_update_all
    else
        read -p "Press Enter to continue..."
    fi
}

# ============================================================================
# Menu Actions
# ============================================================================

menu_create_config() {
    if type run_configuration_wizard &>/dev/null; then
        run_configuration_wizard
    else
        print_error "Configuration wizard not loaded"
        sleep 2
    fi
}

menu_reconfigure() {
    local hostname=$(hostname -s 2>/dev/null | tr '[:upper:]' '[:lower:]')
    if type reconfigure_machine &>/dev/null; then
        reconfigure_machine "$hostname"
    else
        print_error "Reconfigure function not loaded"
        sleep 2
    fi
}

menu_browse_apps() {
    if type browse_homebrew_casks_fzf &>/dev/null; then
        clear
        print_header "Browse Applications"
        echo ""
        echo -e "  ${CYAN}[1]${NC} Browse all applications"
        echo -e "  ${CYAN}[2]${NC} Browse by category"
        echo -e "  ${CYAN}[3]${NC} Search specific apps"
        echo ""
        read -p "$(echo -e ${CYAN}Select${NC} [1]: )" choice
        choice=${choice:-1}

        case "$choice" in
            1) browse_homebrew_casks_fzf "" ;;
            2) browse_by_category ;;
            3)
                read -p "$(echo -e ${CYAN}Search query${NC}: )" query
                browse_homebrew_casks_fzf "$query"
                ;;
        esac
    else
        print_error "Package manager not loaded"
        sleep 2
    fi
}

menu_search_packages() {
    clear
    print_header "Search Packages"
    echo ""
    read -p "$(echo -e ${CYAN}Search query${NC}: )" query

    if [[ -z "$query" ]]; then
        print_warn "No query provided"
        sleep 1
        return
    fi

    echo ""
    print_info "Searching Homebrew casks..."
    brew search --cask "$query" 2>/dev/null | head -20

    echo ""
    print_info "Searching Nix packages..."
    nix --extra-experimental-features "nix-command flakes" search nixpkgs "$query" 2>/dev/null | head -10 || echo "  (nix search requires experimental features)"

    echo ""
    read -p "Press Enter to continue..."
}

menu_update_all() {
    clear
    print_header "Update All Packages"
    echo ""

    if ! ask_yes_no "Update Homebrew packages?" "y"; then
        return
    fi

    print_step "1/3" "Updating Homebrew"
    brew update 2>&1 | tail -20
    echo ""

    print_step "2/3" "Upgrading Homebrew packages"
    brew upgrade 2>&1 | tail -30
    echo ""

    if ask_yes_no "Update Nix flake inputs?" "y"; then
        print_step "3/3" "Updating Nix flake"
        if [[ -d "$CONFIG_DIR" ]]; then
            cd "$CONFIG_DIR"
            nix flake update 2>&1 | tail -20
            print_success "Flake inputs updated"
        fi
    fi

    echo ""
    print_success "Updates complete!"

    if ask_yes_no "Apply configuration changes now?" "y"; then
        menu_apply_changes
    else
        read -p "Press Enter to continue..."
    fi
}

menu_apply_changes() {
    clear
    print_header "Apply Configuration Changes"
    echo ""

    local hostname=$(hostname -s 2>/dev/null | tr '[:upper:]' '[:lower:]')

    if [[ ! -d "$CONFIG_DIR" ]]; then
        print_error "Configuration not found at $CONFIG_DIR"
        sleep 2
        return 1
    fi

    cd "$CONFIG_DIR"

    print_info "Building and applying configuration for $hostname..."
    echo ""

    if darwin-rebuild switch --flake ".#$hostname" 2>&1 | tee /tmp/nix-me-switch.log | tail -50; then
        echo ""
        print_success "Configuration applied successfully!"
    else
        echo ""
        print_error "Configuration failed. Check /tmp/nix-me-switch.log"
    fi

    echo ""
    read -p "Press Enter to continue..."
}

menu_system_status() {
    if type cmd_doctor &>/dev/null; then
        clear
        cmd_doctor
        echo ""
        read -p "Press Enter to continue..."
    else
        inspector_dashboard
    fi
}

menu_rollback() {
    clear
    print_header "Rollback Configuration"
    echo ""

    print_warn "This will revert to the previous generation"
    echo ""

    print_info "Available generations:"
    darwin-rebuild --list-generations 2>/dev/null | tail -10
    echo ""

    if ask_yes_no "Rollback to previous generation?" "n"; then
        print_info "Rolling back..."
        darwin-rebuild --rollback 2>&1 | tail -20
        print_success "Rollback complete"
    else
        print_info "Cancelled"
    fi

    echo ""
    read -p "Press Enter to continue..."
}

menu_vm_management() {
    if type vm_main_menu &>/dev/null; then
        vm_main_menu
    else
        print_error "VM manager not loaded"
        sleep 2
    fi
}

show_help_menu() {
    clear
    print_header "Help"
    echo ""
    echo -e "  ${CYAN}nix-me${NC} - Interactive Nix Configuration Manager"
    echo ""
    echo -e "  ${CYAN}Keyboard Navigation:${NC}"
    echo -e "    • Type number or letter to select option"
    echo -e "    • Press Enter to confirm (uses default in brackets)"
    echo -e "    • Use fzf for interactive selection (if available)"
    echo ""
    echo -e "  ${CYAN}Common Tasks:${NC}"
    echo -e "    • ${GREEN}Inspector${NC} - View current config, packages, status"
    echo -e "    • ${GREEN}Browse${NC} - Add new applications interactively"
    echo -e "    • ${GREEN}Update${NC} - Update all packages (Homebrew + Nix)"
    echo -e "    • ${GREEN}Switch${NC} - Apply configuration changes"
    echo ""
    echo -e "  ${CYAN}CLI Usage:${NC}"
    echo -e "    nix-me           # Open interactive menu"
    echo -e "    nix-me vm        # VM management"
    echo -e "    nix-me browse    # Browse apps"
    echo -e "    nix-me update    # Update packages"
    echo -e "    nix-me switch    # Apply changes"
    echo ""
    read -p "Press Enter to continue..."
}

clean_nix_store() {
    clear
    print_header "Clean Nix Store"
    echo ""

    local store_size=$(du -sh /nix/store 2>/dev/null | cut -f1)
    print_info "Current store size: $store_size"
    echo ""

    if ask_yes_no "Run garbage collection?" "y"; then
        print_info "Collecting garbage..."
        nix-collect-garbage -d 2>&1 | tail -20

        local new_size=$(du -sh /nix/store 2>/dev/null | cut -f1)
        echo ""
        print_success "Store size: $store_size → $new_size"
    fi

    echo ""
    read -p "Press Enter to continue..."
}

# Export main menu
export -f main_menu
