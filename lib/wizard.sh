#!/bin/bash

# Interactive setup wizard for nix-me
# Supports machine types, profiles, and cloning from existing hosts
# Note: Uses bash 3.2 compatible syntax (no associative arrays)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/ui.sh"

# Wizard state variables
WIZARD_SUCCESS=0
WIZARD_MODIFY_ONLY=0
WIZARD_HOSTNAME=""
WIZARD_MACHINE_TYPE=""
WIZARD_MACHINE_NAME=""
WIZARD_USERNAME=""
WIZARD_PROFILES=""  # Space-separated list of profiles
WIZARD_CLONE_FROM=""

# Profile descriptions (bash 3.2 compatible - no associative arrays)
get_profile_description() {
    case "$1" in
        dev)      echo "Development tools, IDEs, and programming languages" ;;
        work)     echo "Work collaboration apps (Slack, Teams, Zoom, etc.)" ;;
        personal) echo "Entertainment and personal apps (Spotify, OBS, etc.)" ;;
        *)        echo "Unknown profile" ;;
    esac
}

# Machine type descriptions (bash 3.2 compatible)
get_machine_type_description() {
    case "$1" in
        macbook)     echo "General MacBook (Air/Pro) - Battery optimized" ;;
        macbook-pro) echo "MacBook Pro - Performance focused" ;;
        macmini)     echo "Mac Mini - Desktop performance, multi-display" ;;
        vm)          echo "Virtual Machine - Minimal, fast boot" ;;
        *)           echo "Unknown machine type" ;;
    esac
}

# Available profiles list
AVAILABLE_PROFILES="dev work personal"

# Available machine types list
AVAILABLE_MACHINE_TYPES="macbook macbook-pro macmini vm"

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
    local repo_dir="$1"
    local hostname="$2"
    local flake_file="$repo_dir/flake.nix"

    if [ ! -f "$flake_file" ]; then
        return
    fi

    # Extract the configuration block for this host
    local in_block=0
    local brace_count=0
    local config=""

    while IFS= read -r line; do
        if [ $in_block -eq 0 ]; then
            if echo "$line" | grep -q "\"$hostname\" = mkDarwinSystem"; then
                in_block=1
                brace_count=0
            fi
        fi

        if [ $in_block -eq 1 ]; then
            config="${config}${line}"$'\n'
            # Count braces
            local open=$(echo "$line" | tr -cd '{' | wc -c)
            local close=$(echo "$line" | tr -cd '}' | wc -c)
            brace_count=$((brace_count + open - close))

            if [ $brace_count -le 0 ] && [ -n "$config" ]; then
                break
            fi
        fi
    done < "$flake_file"

    echo "$config"
}

# Function to extract machine type from config
get_host_machine_type() {
    local config="$1"
    echo "$config" | sed -n 's/.*machineType *= *"\([^"]*\)".*/\1/p' | head -1
}

# Function to extract profiles from config
get_host_profiles() {
    local config="$1"
    echo "$config" | grep -o './hosts/profiles/[^"]*\.nix' | \
        sed 's|.*/||; s|\.nix||' | \
        sort -u
}

# Function to prompt for clone from existing host
prompt_clone_from_host() {
    local repo_dir="${1:-$HOME/.config/nixpkgs}"

    print_header "Clone from Existing Host"
    echo ""

    local hosts_list=$(get_existing_hosts "$repo_dir")

    if [ -z "$hosts_list" ]; then
        print_warn "No existing hosts found in flake.nix"
        return 1
    fi

    print_info "Available hosts to clone from:"
    echo ""

    local i=1
    local hosts_array=""
    for host in $hosts_list; do
        echo "  [$i] $host"
        hosts_array="$hosts_array $host"
        i=$((i + 1))
    done
    hosts_array=$(echo "$hosts_array" | sed 's/^ //')

    local host_count=$((i - 1))
    echo ""
    read -p "$(echo -e ${CYAN}Select host to clone \(1-${host_count}\): ${NC})" host_choice

    if [ -n "$host_choice" ] && [ "$host_choice" -ge 1 ] 2>/dev/null && [ "$host_choice" -le "$host_count" ] 2>/dev/null; then
        # Get the nth host
        local selected_host=$(echo "$hosts_array" | cut -d' ' -f"$host_choice")
        WIZARD_CLONE_FROM="$selected_host"

        # Get the source host's configuration
        local config=$(get_host_config "$repo_dir" "$WIZARD_CLONE_FROM")
        WIZARD_MACHINE_TYPE=$(get_host_machine_type "$config")

        # Get profiles as space-separated string
        WIZARD_PROFILES=$(get_host_profiles "$config" | tr '\n' ' ' | sed 's/ $//')

        print_success "Will clone settings from: $WIZARD_CLONE_FROM"
        echo "  Machine type: $WIZARD_MACHINE_TYPE"
        if [ -n "$WIZARD_PROFILES" ]; then
            echo "  Profiles: $WIZARD_PROFILES"
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

    local available_list=$(get_available_profiles)

    if [ -z "$available_list" ]; then
        # Fall back to known profiles
        available_list="dev work personal"
    fi

    local i=1
    local available_array=""
    for profile in $available_list; do
        local desc=$(get_profile_description "$profile")
        echo "  [$i] $profile - $desc"
        available_array="$available_array $profile"
        i=$((i + 1))
    done
    available_array=$(echo "$available_array" | sed 's/^ //')

    echo ""
    echo "  Example: 1,2 for dev+work, or just 1 for dev only"
    echo ""

    read -p "$(echo -e ${CYAN}Select profiles \(comma-separated, or Enter for none\): ${NC})" profile_choices

    if [ -z "$profile_choices" ]; then
        WIZARD_PROFILES=""
        print_info "Using minimal base configuration (no profiles)"
    else
        WIZARD_PROFILES=""
        local profile_count=$(echo "$available_array" | wc -w | tr -d ' ')

        # Split by comma
        local IFS_OLD="$IFS"
        IFS=','
        for choice in $profile_choices; do
            IFS="$IFS_OLD"
            choice=$(echo "$choice" | tr -d ' ')
            if [ -n "$choice" ] && [ "$choice" -ge 1 ] 2>/dev/null && [ "$choice" -le "$profile_count" ] 2>/dev/null; then
                local selected=$(echo "$available_array" | cut -d' ' -f"$choice")
                if [ -n "$WIZARD_PROFILES" ]; then
                    WIZARD_PROFILES="$WIZARD_PROFILES $selected"
                else
                    WIZARD_PROFILES="$selected"
                fi
            fi
            IFS=','
        done
        IFS="$IFS_OLD"

        if [ -n "$WIZARD_PROFILES" ]; then
            print_success "Selected profiles: $WIZARD_PROFILES"
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
    local type_keys=""

    for mtype in macbook macbook-pro macmini vm; do
        type_keys="$type_keys $mtype"
        local desc=$(get_machine_type_description "$mtype")
        echo "  [$i] $mtype - $desc"
        i=$((i + 1))
    done
    type_keys=$(echo "$type_keys" | sed 's/^ //')

    echo ""

    # Auto-detect default
    local default_type="macbook"
    if [ "${VM_TYPE:-physical}" != "physical" ]; then
        default_type="vm"
    fi

    local default_num=1
    case "$default_type" in
        macbook)     default_num=1 ;;
        macbook-pro) default_num=2 ;;
        macmini)     default_num=3 ;;
        vm)          default_num=4 ;;
    esac

    read -p "$(echo -e ${CYAN}Select machine type ${NC}[${default_num}]: )" type_choice
    type_choice=${type_choice:-$default_num}

    if [ -n "$type_choice" ] && [ "$type_choice" -ge 1 ] 2>/dev/null && [ "$type_choice" -le 4 ] 2>/dev/null; then
        WIZARD_MACHINE_TYPE=$(echo "$type_keys" | cut -d' ' -f"$type_choice")
        print_success "Selected: $WIZARD_MACHINE_TYPE"
    else
        WIZARD_MACHINE_TYPE="$default_type"
        print_info "Using default: $WIZARD_MACHINE_TYPE"
    fi
}

# Main wizard function
run_setup_wizard() {
    local repo_dir="${1:-$HOME/.config/nixpkgs}"
    local cloning=0

    print_header "nix-me Setup Wizard"
    echo ""

    # Check for existing hosts
    local existing_hosts=$(get_existing_hosts "$repo_dir")

    if [ -n "$existing_hosts" ]; then
        print_info "How would you like to set up this machine?"
        echo ""
        echo "  [1] Create new configuration from scratch"
        echo "  [2] Clone settings from an existing host"
        echo ""

        read -p "$(echo -e ${CYAN}Choose \(1-2\) ${NC}[1]: )" setup_choice
        setup_choice=${setup_choice:-1}

        if [ "$setup_choice" = "2" ]; then
            if prompt_clone_from_host "$repo_dir"; then
                cloning=1
            else
                print_info "Falling back to new configuration"
            fi
        fi
    fi

    # Step 1: Hostname
    local default_hostname
    if [ "${VM_TYPE:-physical}" != "physical" ]; then
        default_hostname="nix-darwin-vm"
    else
        default_hostname=$(hostname -s 2>/dev/null | tr '[:upper:]' '[:lower:]' || echo "my-mac")
    fi

    print_header "Machine Configuration"
    echo ""

    read -p "$(echo -e ${CYAN}Hostname ${NC}[${default_hostname}]: )" input_hostname
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

    # Step 3: Machine Display Name
    local default_name="$WIZARD_HOSTNAME"
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
        if [ -n "$WIZARD_PROFILES" ]; then
            print_info "Profiles from clone: $WIZARD_PROFILES"
        else
            print_info "Profiles from clone: (minimal)"
        fi
        if ! ask_yes_no "Keep these profiles?" "y"; then
            WIZARD_PROFILES=""
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
    if [ -n "$WIZARD_PROFILES" ]; then
        echo "  Profiles:      $WIZARD_PROFILES"
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
        # Convert space-separated profiles to arguments
        generate_machine_config_multi_profile \
            "$WIZARD_HOSTNAME" \
            "$WIZARD_MACHINE_TYPE" \
            "$WIZARD_MACHINE_NAME" \
            "$WIZARD_USERNAME" \
            "$repo_dir" \
            $WIZARD_PROFILES
    else
        print_warn "Config builder not found, configuration needs manual setup"
    fi

    WIZARD_SUCCESS=1
    return 0
}

# Export functions for use by other scripts
export -f run_setup_wizard 2>/dev/null || true
export -f prompt_profile_selection 2>/dev/null || true
export -f prompt_machine_type_selection 2>/dev/null || true
export -f prompt_clone_from_host 2>/dev/null || true
export -f get_existing_hosts 2>/dev/null || true
