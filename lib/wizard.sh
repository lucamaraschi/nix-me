#!/bin/bash

# Interactive setup wizard for nix-me
# Supports machine types, profiles, and cloning from existing hosts

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/ui.sh"

# Wizard state variables
WIZARD_SUCCESS=0
WIZARD_MODIFY_ONLY=0
WIZARD_HOSTNAME=""
WIZARD_MACHINE_TYPE=""
WIZARD_MACHINE_NAME=""
WIZARD_USERNAME=""
WIZARD_PROFILES=()  # Array of profiles (supports multiple)
WIZARD_CLONE_FROM=""

# Available profiles (composable)
declare -A PROFILES=(
    ["dev"]="Development tools, IDEs, and programming languages"
    ["work"]="Work collaboration apps (Slack, Teams, Zoom, etc.)"
    ["personal"]="Entertainment and personal apps (Spotify, OBS, etc.)"
)

# Available machine types
declare -A MACHINE_TYPES=(
    ["macbook"]="General MacBook (Air/Pro) - Battery optimized"
    ["macbook-pro"]="MacBook Pro - Performance focused"
    ["macmini"]="Mac Mini - Desktop performance, multi-display"
    ["vm"]="Virtual Machine - Minimal, fast boot"
)

# Function to get existing hosts from flake.nix
get_existing_hosts() {
    local repo_dir="${1:-$HOME/.config/nixpkgs}"
    local flake_file="$repo_dir/flake.nix"

    if [ ! -f "$flake_file" ]; then
        return
    fi

    # Extract host names from darwinConfigurations
    grep -E '^\s+"[a-zA-Z0-9_-]+" = mkDarwinSystem' "$flake_file" | \
        sed -E 's/.*"([^"]+)".*/\1/' | \
        sort -u
}

# Function to get host configuration details
get_host_config() {
    local repo_dir="${1:-$HOME/.config/nixpkgs}"
    local hostname="$2"
    local flake_file="$repo_dir/flake.nix"

    if [ ! -f "$flake_file" ]; then
        return
    fi

    # Extract the configuration block for this host
    local in_block=0
    local brace_count=0
    local block_content=""

    while IFS= read -r line; do
        if [[ "$line" =~ \"$hostname\"\ =\ mkDarwinSystem ]]; then
            in_block=1
            brace_count=0
        fi
        if [ $in_block -eq 1 ]; then
            block_content+="$line"$'\n'
            # Count opening braces
            local opens=$(echo "$line" | tr -cd '{' | wc -c)
            local closes=$(echo "$line" | tr -cd '}' | wc -c)
            brace_count=$((brace_count + opens - closes))

            # Stop when braces are balanced (back to 0)
            if [ $brace_count -le 0 ] && [ -n "$block_content" ]; then
                break
            fi
        fi
    done < "$flake_file"

    echo "$block_content"
}

# Function to extract machine type from host config
get_host_machine_type() {
    local config="$1"
    # Use sed instead of grep -P for macOS compatibility
    echo "$config" | sed -n 's/.*machineType *= *"\([^"]*\)".*/\1/p' | head -1
    # Default to macbook if not found
    if [ -z "$(echo "$config" | sed -n 's/.*machineType *= *"\([^"]*\)".*/\1/p')" ]; then
        echo "macbook"
    fi
}

# Function to extract profiles from host config
get_host_profiles() {
    local config="$1"
    # Use sed instead of grep -P for macOS compatibility
    echo "$config" | sed -n 's/.*profiles\/\([^.]*\)\.nix.*/\1/p' | sort -u
}

# Function to prompt for cloning from existing host
prompt_clone_from_host() {
    local repo_dir="${1:-$HOME/.config/nixpkgs}"

    local hosts=($(get_existing_hosts "$repo_dir"))

    if [ ${#hosts[@]} -eq 0 ]; then
        return 1  # No existing hosts
    fi

    print_header "Setup Method"
    echo ""
    echo "  [1] Create new configuration from scratch"
    echo "  [2] Clone settings from an existing host"
    echo ""

    read -p "$(echo -e ${CYAN}Choose setup method ${NC}[1]: )" method_choice
    method_choice=${method_choice:-1}

    if [ "$method_choice" != "2" ]; then
        return 1  # User chose to create from scratch
    fi

    # Show existing hosts
    print_header "Select Host to Clone From"
    echo ""
    print_info "Available hosts:"
    echo ""

    local i=1
    for host in "${hosts[@]}"; do
        local config=$(get_host_config "$repo_dir" "$host")
        local mtype=$(get_host_machine_type "$config")
        local profiles=$(get_host_profiles "$config" | tr '\n' ', ' | sed 's/,$//')

        if [ -n "$profiles" ]; then
            echo "  [$i] $host ($mtype) - profiles: $profiles"
        else
            echo "  [$i] $host ($mtype) - minimal"
        fi
        ((i++))
    done

    echo ""
    read -p "$(echo -e ${CYAN}Select host to clone \(1-${#hosts[@]}\): )" host_choice

    if [[ "$host_choice" =~ ^[0-9]+$ ]] && [ "$host_choice" -ge 1 ] && [ "$host_choice" -le "${#hosts[@]}" ]; then
        WIZARD_CLONE_FROM="${hosts[$((host_choice - 1))]}"

        # Get the source host's configuration
        local config=$(get_host_config "$repo_dir" "$WIZARD_CLONE_FROM")
        WIZARD_MACHINE_TYPE=$(get_host_machine_type "$config")

        # Get profiles as array
        while IFS= read -r profile; do
            [ -n "$profile" ] && WIZARD_PROFILES+=("$profile")
        done < <(get_host_profiles "$config")

        print_success "Will clone settings from: $WIZARD_CLONE_FROM"
        echo "  Machine type: $WIZARD_MACHINE_TYPE"
        if [ ${#WIZARD_PROFILES[@]} -gt 0 ]; then
            echo "  Profiles: ${WIZARD_PROFILES[*]}"
        else
            echo "  Profiles: (minimal)"
        fi
        echo ""

        return 0
    else
        print_warn "Invalid selection"
        return 1
    fi
}

# Function to detect available profiles
get_available_profiles() {
    local repo_dir="${1:-$HOME/.config/nixpkgs}"
    local profiles_dir="$repo_dir/hosts/profiles"

    if [ ! -d "$profiles_dir" ]; then
        echo ""
        return
    fi

    # List all .nix files in profiles directory
    for profile_file in "$profiles_dir"/*.nix; do
        if [ -f "$profile_file" ]; then
            basename "$profile_file" .nix
        fi
    done
}

# Function to prompt for multiple profile selection
prompt_profile_selection() {
    print_header "Select Configuration Profiles"
    echo ""
    print_info "Profiles are composable - select all that apply"
    print_info "Press Enter with no selection for minimal (base only)"
    echo ""

    local available=($(get_available_profiles))

    if [ ${#available[@]} -eq 0 ]; then
        # Fall back to known profiles
        available=(dev work personal)
    fi

    local i=1
    for profile in "${available[@]}"; do
        local desc="${PROFILES[$profile]:-No description}"
        echo "  [$i] $profile - $desc"
        ((i++))
    done

    echo ""
    echo "  Example: 1,2 for dev+work, or just 1 for dev only"
    echo ""

    read -p "$(echo -e ${CYAN}Select profiles \(comma-separated, or Enter for none\): )" profile_choices

    if [ -z "$profile_choices" ]; then
        WIZARD_PROFILES=()
        print_info "Using minimal base configuration (no profiles)"
    else
        IFS=',' read -ra choices <<< "$profile_choices"
        for choice in "${choices[@]}"; do
            choice=$(echo "$choice" | tr -d ' ')
            if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#available[@]}" ]; then
                WIZARD_PROFILES+=("${available[$((choice - 1))]}")
            fi
        done

        if [ ${#WIZARD_PROFILES[@]} -gt 0 ]; then
            print_success "Selected profiles: ${WIZARD_PROFILES[*]}"
        else
            print_info "Using minimal base configuration"
        fi
    fi
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

    # Reset state
    WIZARD_PROFILES=()
    WIZARD_CLONE_FROM=""

    # Step 0: Check for existing hosts and offer to clone
    local cloning=0
    if prompt_clone_from_host "$repo_dir"; then
        cloning=1
    fi

    # Step 1: Hostname
    local default_hostname
    if [ "$VM_TYPE" != "physical" ]; then
        default_hostname="nix-darwin-vm"
    else
        default_hostname=$(hostname -s | tr '[:upper:]' '[:lower:]')
    fi

    echo ""
    read -p "$(echo -e ${CYAN}Hostname for this machine ${NC}[${default_hostname}]: )" input_hostname
    WIZARD_HOSTNAME=${input_hostname:-$default_hostname}

    # Step 2: Machine Type (skip if cloning - already set)
    if [ $cloning -eq 0 ]; then
        prompt_machine_type_selection
    else
        echo ""
        print_info "Machine type from clone: $WIZARD_MACHINE_TYPE"
        if ! ask_yes_no "Keep this machine type?" "y"; then
            prompt_machine_type_selection
        fi
    fi

    # Step 3: Machine Name (display name)
    local default_name="$WIZARD_HOSTNAME"
    echo ""
    read -p "$(echo -e ${CYAN}Machine Display Name ${NC}[${default_name}]: )" input_name
    WIZARD_MACHINE_NAME=${input_name:-$default_name}

    # Step 4: Username
    local default_user=$(whoami)
    read -p "$(echo -e ${CYAN}Username ${NC}[${default_user}]: )" input_user
    WIZARD_USERNAME=${input_user:-$default_user}

    # Step 5: Profile Selection (skip if cloning - already set)
    if [ $cloning -eq 0 ]; then
        prompt_profile_selection
    else
        echo ""
        if [ ${#WIZARD_PROFILES[@]} -gt 0 ]; then
            print_info "Profiles from clone: ${WIZARD_PROFILES[*]}"
        else
            print_info "Profiles from clone: (minimal)"
        fi
        if ! ask_yes_no "Keep these profiles?" "y"; then
            WIZARD_PROFILES=()
            prompt_profile_selection
        fi
    fi

    # Summary
    echo ""
    print_header "Configuration Summary"
    echo ""
    echo "  Hostname:      $WIZARD_HOSTNAME"
    echo "  Machine Type:  $WIZARD_MACHINE_TYPE"
    echo "  Display Name:  $WIZARD_MACHINE_NAME"
    echo "  Username:      $WIZARD_USERNAME"
    if [ ${#WIZARD_PROFILES[@]} -gt 0 ]; then
        echo "  Profiles:      ${WIZARD_PROFILES[*]}"
    else
        echo "  Profiles:      (minimal base only)"
    fi
    if [ -n "$WIZARD_CLONE_FROM" ]; then
        echo "  Cloned from:   $WIZARD_CLONE_FROM"
    fi
    echo ""

    if ! ask_yes_no "Proceed with this configuration?"; then
        print_error "Setup cancelled"
        WIZARD_SUCCESS=0
        return 1
    fi

    # Generate configuration
    echo ""
    print_info "Generating configuration files..."

    if [ -f "$repo_dir/lib/config-builder.sh" ]; then
        source "$repo_dir/lib/config-builder.sh"
        generate_machine_config_multi_profile \
            "$WIZARD_HOSTNAME" \
            "$WIZARD_MACHINE_TYPE" \
            "$WIZARD_MACHINE_NAME" \
            "$WIZARD_USERNAME" \
            "$repo_dir" \
            "${WIZARD_PROFILES[@]}"
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
export -f prompt_clone_from_host
export -f get_existing_hosts
