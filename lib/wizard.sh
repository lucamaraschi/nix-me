#!/bin/bash

# Interactive setup wizard for nix-me
# Supports machine types and profiles

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/ui.sh"

# Wizard state variables
WIZARD_SUCCESS=0
WIZARD_MODIFY_ONLY=0
WIZARD_HOSTNAME=""
WIZARD_MACHINE_TYPE=""
WIZARD_MACHINE_NAME=""
WIZARD_USERNAME=""
WIZARD_PROFILE=""

# Available profiles
declare -A PROFILES=(
    ["work"]="Work environment with productivity and collaboration tools"
    ["personal"]="Personal setup with entertainment and creative apps"
    ["minimal"]="Minimal configuration without profile customizations"
    ["custom"]="Create your own profile configuration"
)

# Available machine types
declare -A MACHINE_TYPES=(
    ["macbook"]="General MacBook (Air/Pro) - Battery optimized"
    ["macbook-pro"]="MacBook Pro - Performance focused, inherits from macbook"
    ["macmini"]="Mac Mini - Desktop performance, multi-display"
    ["vm"]="Virtual Machine - Minimal, fast boot"
)

# Function to detect available profiles
get_available_profiles() {
    local repo_dir="${1:-$HOME/.config/nixpkgs}"
    local profiles_dir="$repo_dir/hosts/profiles"

    if [ ! -d "$profiles_dir" ]; then
        echo "minimal"
        return
    fi

    # List all .nix files in profiles directory
    for profile_file in "$profiles_dir"/*.nix; do
        if [ -f "$profile_file" ]; then
            basename "$profile_file" .nix
        fi
    done
}

# Function to prompt for profile selection
prompt_profile_selection() {
    print_header "Select Configuration Profile"
    echo ""
    print_info "Profiles customize your system for specific use cases"
    echo ""

    local i=1
    local -a profile_keys=()

    for profile in "${!PROFILES[@]}"; do
        profile_keys+=("$profile")
        echo "  [$i] $profile - ${PROFILES[$profile]}"
        ((i++))
    done

    echo ""
    read -p "$(echo -e ${CYAN}Select profile \(1-${#PROFILES[@]}\) ${NC}[1]: )" profile_choice
    profile_choice=${profile_choice:-1}

    if [[ "$profile_choice" =~ ^[0-9]+$ ]] && [ "$profile_choice" -ge 1 ] && [ "$profile_choice" -le "${#PROFILES[@]}" ]; then
        WIZARD_PROFILE="${profile_keys[$((profile_choice - 1))]}"
    else
        print_warn "Invalid selection, using 'minimal'"
        WIZARD_PROFILE="minimal"
    fi

    print_success "Selected profile: $WIZARD_PROFILE"
}

# Function to prompt for machine type selection
prompt_machine_type_selection() {
    print_header "Select Machine Type"
    echo ""
    print_info "Machine types provide hardware-specific optimizations"
    echo ""

    local i=1
    local -a type_keys=()

    for mtype in macbook macbook-pro macmini vm; do
        type_keys+=("$mtype")
        echo "  [$i] $mtype - ${MACHINE_TYPES[$mtype]}"
        ((i++))
    done

    echo ""

    # Auto-detect default
    local default_type="macbook"
    if [ "$VM_TYPE" != "physical" ]; then
        default_type="vm"
    fi

    read -p "$(echo -e ${CYAN}Select machine type \(1-${#type_keys[@]}\) ${NC}[${default_type}]: )" type_choice

    if [ -z "$type_choice" ]; then
        WIZARD_MACHINE_TYPE="$default_type"
    elif [[ "$type_choice" =~ ^[0-9]+$ ]] && [ "$type_choice" -ge 1 ] && [ "$type_choice" -le "${#type_keys[@]}" ]; then
        WIZARD_MACHINE_TYPE="${type_keys[$((type_choice - 1))]}"
    else
        print_warn "Invalid selection, using '$default_type'"
        WIZARD_MACHINE_TYPE="$default_type"
    fi

    print_success "Selected machine type: $WIZARD_MACHINE_TYPE"
}

# Main wizard function
run_setup_wizard() {
    local repo_dir="${1:-$HOME/.config/nixpkgs}"

    print_header "nix-me Configuration Wizard"
    echo ""
    print_info "This wizard will help you configure your macOS system"
    echo ""

    # Step 1: Hostname
    local default_hostname
    if [ "$VM_TYPE" != "physical" ]; then
        default_hostname="nix-darwin-vm"
    else
        default_hostname=$(hostname -s | tr '[:upper:]' '[:lower:]')
    fi

    read -p "$(echo -e ${CYAN}Hostname ${NC}[${default_hostname}]: )" input_hostname
    WIZARD_HOSTNAME=${input_hostname:-$default_hostname}

    # Step 2: Machine Type
    prompt_machine_type_selection

    # Step 3: Machine Name (display name)
    local default_name="$WIZARD_HOSTNAME"
    read -p "$(echo -e ${CYAN}Machine Display Name ${NC}[${default_name}]: )" input_name
    WIZARD_MACHINE_NAME=${input_name:-$default_name}

    # Step 4: Username
    local default_user=$(whoami)
    read -p "$(echo -e ${CYAN}Username ${NC}[${default_user}]: )" input_user
    WIZARD_USERNAME=${input_user:-$default_user}

    # Step 5: Profile Selection
    prompt_profile_selection

    # Summary
    echo ""
    print_header "Configuration Summary"
    echo "  Hostname:      $WIZARD_HOSTNAME"
    echo "  Machine Type:  $WIZARD_MACHINE_TYPE"
    echo "  Display Name:  $WIZARD_MACHINE_NAME"
    echo "  Username:      $WIZARD_USERNAME"
    echo "  Profile:       $WIZARD_PROFILE"
    echo ""

    if ! ask_yes_no "Proceed with this configuration?"; then
        print_error "Setup cancelled"
        WIZARD_SUCCESS=0
        return 1
    fi

    # Generate configuration
    print_info "Generating configuration files..."

    if [ -f "$repo_dir/lib/config-builder.sh" ]; then
        source "$repo_dir/lib/config-builder.sh"
        generate_machine_config_with_profile \
            "$WIZARD_HOSTNAME" \
            "$WIZARD_MACHINE_TYPE" \
            "$WIZARD_MACHINE_NAME" \
            "$WIZARD_USERNAME" \
            "$WIZARD_PROFILE" \
            "$repo_dir"
    else
        print_warn "Config builder not found, configuration needs manual setup"
    fi

    WIZARD_SUCCESS=1
    return 0
}

# Export functions for use by other scripts
export -f run_setup_wizard
export -f prompt_profile_selection
export -f prompt_machine_type_selection
