#!/bin/bash

# Enhanced configuration wizard with profile support and package selection

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/ui.sh"
source "$SCRIPT_DIR/config-builder.sh"
source "$SCRIPT_DIR/package-manager.sh"

CONFIG_DIR="${HOME}/.config/nixpkgs"

# Wizard state
WIZARD_HOSTNAME=""
WIZARD_MACHINE_TYPE=""
WIZARD_MACHINE_NAME=""
WIZARD_USERNAME=""
WIZARD_PROFILE=""
WIZARD_PACKAGES=()

# Enhanced profile selection with descriptions
select_profile() {
    print_header "Select Configuration Profile"
    echo ""
    print_info "Profiles provide pre-configured app collections for specific use cases"
    echo ""

    if command -v fzf &>/dev/null; then
        # Use fzf for nice selection
        local profiles=(
            "work:Work environment (Teams, Slack, Office, Docker, Dev tools)"
            "personal:Personal setup (Spotify, Creative apps, Entertainment)"
            "minimal:Clean slate - choose your own apps"
            "custom:Create a custom profile"
        )

        local selected=$(printf '%s\n' "${profiles[@]}" | \
            fzf --height=50% \
                --border=rounded \
                --prompt="Select profile > " \
                --header="Choose your configuration profile" \
                --delimiter=":" \
                --with-nth=1 \
                --preview='echo {2}' \
                --preview-window=down:3:wrap
        )

        if [ -z "$selected" ]; then
            print_error "No profile selected"
            return 1
        fi

        WIZARD_PROFILE=$(echo "$selected" | cut -d: -f1)
    else
        # Fallback to simple selection
        echo "  ${CYAN}1${NC}) Work - Productivity and collaboration tools"
        echo "  ${CYAN}2${NC}) Personal - Entertainment and creative apps"
        echo "  ${CYAN}3${NC}) Minimal - Start with basics, add as needed"
        echo "  ${CYAN}4${NC}) Custom - Create your own profile"
        echo ""

        read -p "Select profile [1-4]: " choice

        case $choice in
            1) WIZARD_PROFILE="work" ;;
            2) WIZARD_PROFILE="personal" ;;
            3) WIZARD_PROFILE="minimal" ;;
            4) WIZARD_PROFILE="custom" ;;
            *)
                print_error "Invalid selection"
                return 1
                ;;
        esac
    fi

    print_success "Selected profile: $WIZARD_PROFILE"
    return 0
}

# Select machine type
select_machine_type() {
    print_header "Select Machine Type"
    echo ""
    print_info "Machine types provide hardware-specific optimizations"
    echo ""

    if command -v fzf &>/dev/null; then
        local types=(
            "macbook:General MacBook - Battery optimized, portable"
            "macbook-pro:MacBook Pro - Performance focused, Pro features"
            "macmini:Mac Mini - Desktop power, multi-display"
            "vm:Virtual Machine - Minimal, fast boot"
        )

        local selected=$(printf '%s\n' "${types[@]}" | \
            fzf --height=50% \
                --border=rounded \
                --prompt="Select type > " \
                --header="Choose your machine type" \
                --delimiter=":" \
                --with-nth=1 \
                --preview='echo {2}' \
                --preview-window=down:3:wrap
        )

        if [ -z "$selected" ]; then
            print_error "No type selected"
            return 1
        fi

        WIZARD_MACHINE_TYPE=$(echo "$selected" | cut -d: -f1)
    else
        echo "  ${CYAN}1${NC}) macbook - General MacBook (Air/Pro)"
        echo "  ${CYAN}2${NC}) macbook-pro - MacBook Pro with Pro optimizations"
        echo "  ${CYAN}3${NC}) macmini - Mac Mini desktop"
        echo "  ${CYAN}4${NC}) vm - Virtual Machine"
        echo ""

        read -p "Select type [1-4]: " choice

        case $choice in
            1) WIZARD_MACHINE_TYPE="macbook" ;;
            2) WIZARD_MACHINE_TYPE="macbook-pro" ;;
            3) WIZARD_MACHINE_TYPE="macmini" ;;
            4) WIZARD_MACHINE_TYPE="vm" ;;
            *)
                print_error "Invalid selection"
                return 1
                ;;
        esac
    fi

    print_success "Selected type: $WIZARD_MACHINE_TYPE"
    return 0
}

# Interactive package selection
select_packages() {
    print_header "Select Additional Applications"
    echo ""

    if [ "$WIZARD_PROFILE" == "minimal" ] || [ "$WIZARD_PROFILE" == "custom" ]; then
        print_info "Select applications to install on this machine"
    else
        print_info "Your profile includes default apps. Add more if needed."
    fi

    echo ""
    echo "How would you like to select apps?"
    echo ""
    echo "  ${CYAN}1${NC}) Browse all apps with search"
    echo "  ${CYAN}2${NC}) Browse by category"
    echo "  ${CYAN}3${NC}) Search for specific apps"
    echo "  ${CYAN}4${NC}) Skip - use profile defaults"
    echo ""

    read -p "Choice [4]: " choice
    choice=${choice:-4}

    case $choice in
        1)
            if command -v fzf &>/dev/null; then
                print_info "Loading app browser..."
                local selected=$(browse_homebrew_casks_fzf "")
                if [ -n "$selected" ]; then
                    readarray -t WIZARD_PACKAGES <<< "$selected"
                fi
            else
                print_warn "fzf not available, falling back to simple mode"
                print_info "Enter app names (comma-separated):"
                read -p "> " apps
                IFS=',' read -ra WIZARD_PACKAGES <<< "$apps"
            fi
            ;;
        2)
            browse_by_category
            local selected=$(browse_by_category)
            if [ -n "$selected" ]; then
                readarray -t WIZARD_PACKAGES <<< "$selected"
            fi
            ;;
        3)
            read -p "Search for (e.g., 'docker', 'spotify'): " query
            if command -v fzf &>/dev/null; then
                local selected=$(browse_homebrew_casks_fzf "$query")
                if [ -n "$selected" ]; then
                    readarray -t WIZARD_PACKAGES <<< "$selected"
                fi
            else
                local selected=$(browse_homebrew_casks_simple "$query")
                if [ -n "$selected" ]; then
                    readarray -t WIZARD_PACKAGES <<< "$selected"
                fi
            fi
            ;;
        4)
            print_info "Using profile defaults"
            ;;
        *)
            print_warn "Invalid choice, using defaults"
            ;;
    esac

    if [ ${#WIZARD_PACKAGES[@]} -gt 0 ]; then
        print_success "Selected ${#WIZARD_PACKAGES[@]} additional apps"
    fi

    return 0
}

# Main configuration wizard
run_configuration_wizard() {
    clear
    print_header "🎉 nix-me Configuration Wizard"
    echo ""
    print_info "Let's set up your macOS configuration!"
    echo ""

    # Step 1: Basic Info
    print_step "1/6" "Basic Information"
    echo ""

    local default_hostname=$(hostname -s | tr '[:upper:]' '[:lower:]')
    read -p "$(echo -e ${CYAN}Hostname ${NC}[${default_hostname}]: )" input_hostname
    WIZARD_HOSTNAME=${input_hostname:-$default_hostname}

    local default_user=$(whoami)
    read -p "$(echo -e ${CYAN}Username ${NC}[${default_user}]: )" input_user
    WIZARD_USERNAME=${input_user:-$default_user}

    local default_name="$WIZARD_HOSTNAME"
    read -p "$(echo -e ${CYAN}Display Name ${NC}[${default_name}]: )" input_name
    WIZARD_MACHINE_NAME=${input_name:-$default_name}

    echo ""

    # Step 2: Machine Type
    print_step "2/6" "Machine Type"
    echo ""
    select_machine_type || return 1
    echo ""

    # Step 3: Profile
    print_step "3/6" "Configuration Profile"
    echo ""
    select_profile || return 1
    echo ""

    # Step 4: Package Selection
    print_step "4/6" "Application Selection"
    echo ""
    select_packages
    echo ""

    # Step 5: Summary
    print_step "5/6" "Configuration Summary"
    echo ""
    echo "  ${CYAN}Hostname:${NC}      $WIZARD_HOSTNAME"
    echo "  ${CYAN}Username:${NC}      $WIZARD_USERNAME"
    echo "  ${CYAN}Display Name:${NC}  $WIZARD_MACHINE_NAME"
    echo "  ${CYAN}Machine Type:${NC}  $WIZARD_MACHINE_TYPE"
    echo "  ${CYAN}Profile:${NC}       $WIZARD_PROFILE"

    if [ ${#WIZARD_PACKAGES[@]} -gt 0 ]; then
        echo "  ${CYAN}Extra Apps:${NC}    ${#WIZARD_PACKAGES[@]} selected"
    fi

    echo ""

    if ! ask_yes_no "Create this configuration?" "y"; then
        print_error "Configuration cancelled"
        return 1
    fi

    # Step 6: Generate Configuration
    print_step "6/6" "Generating Configuration"
    echo ""

    # Generate the configuration
    generate_machine_config_with_profile \
        "$WIZARD_HOSTNAME" \
        "$WIZARD_MACHINE_TYPE" \
        "$WIZARD_MACHINE_NAME" \
        "$WIZARD_USERNAME" \
        "$WIZARD_PROFILE" \
        "$CONFIG_DIR"

    # Add extra packages if selected
    if [ ${#WIZARD_PACKAGES[@]} -gt 0 ]; then
        print_info "Adding selected applications..."
        add_casks_to_config "$WIZARD_HOSTNAME" "${WIZARD_PACKAGES[@]}"
    fi

    echo ""
    print_success "✅ Configuration created successfully!"
    echo ""
    print_info "Configuration location: $CONFIG_DIR/hosts/$WIZARD_HOSTNAME"
    echo ""
    print_header "Next Steps"
    echo ""
    echo "  1. Review your configuration:"
    echo "     ${CYAN}cat $CONFIG_DIR/hosts/$WIZARD_HOSTNAME/default.nix${NC}"
    echo ""
    echo "  2. Build the configuration:"
    echo "     ${CYAN}cd $CONFIG_DIR && make build HOST=$WIZARD_HOSTNAME${NC}"
    echo ""
    echo "  3. Apply the configuration:"
    echo "     ${CYAN}nix-me switch${NC}"
    echo ""

    return 0
}

# Quick reconfigure - modify existing machine
reconfigure_machine() {
    local hostname="${1:-$(hostname -s | tr '[:upper:]' '[:lower:]')}"

    print_header "Reconfigure Machine: $hostname"
    echo ""

    local host_dir="$CONFIG_DIR/hosts/$hostname"

    if [ ! -d "$host_dir" ]; then
        print_error "Configuration not found for: $hostname"
        echo ""
        print_info "Available configurations:"
        ls -1 "$CONFIG_DIR/hosts" 2>/dev/null | grep -v "shared\|macbook\|macmini\|vm\|profiles" || echo "None"
        return 1
    fi

    echo "What would you like to modify?"
    echo ""
    echo "  ${CYAN}1${NC}) Add applications"
    echo "  ${CYAN}2${NC}) Change profile"
    echo "  ${CYAN}3${NC}) Edit configuration file"
    echo "  ${CYAN}0${NC}) Cancel"
    echo ""

    read -p "Choice: " choice

    case $choice in
        1)
            print_info "Browsing applications..."
            local selected=$(browse_homebrew_casks_fzf "")
            if [ -n "$selected" ]; then
                local packages=()
                readarray -t packages <<< "$selected"
                add_casks_to_config "$hostname" "${packages[@]}"
            fi
            ;;
        2)
            print_info "Profile switching not yet implemented"
            print_info "Manually edit: $CONFIG_DIR/flake.nix"
            ;;
        3)
            ${EDITOR:-nano} "$host_dir/default.nix"
            ;;
        0)
            print_info "Cancelled"
            return 0
            ;;
        *)
            print_error "Invalid choice"
            return 1
            ;;
    esac
}

# Export functions
export -f run_configuration_wizard
export -f reconfigure_machine
export -f select_packages
