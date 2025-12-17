#!/bin/bash

# Interactive setup wizard for nix-me
# Supports selecting pre-made configs or creating new ones
# Note: Uses bash 3.2 compatible syntax (no associative arrays)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/ui.sh"

# Wizard state variables
WIZARD_SUCCESS=0
WIZARD_HOSTNAME=""
WIZARD_MACHINE_TYPE=""
WIZARD_MACHINE_NAME=""
WIZARD_USERNAME=""
WIZARD_PROFILES=""
WIZARD_SELECTED_HOST=""

# Colors
CYAN='\033[0;36m'
NC='\033[0m'

# Function to get existing hosts from flake.nix
get_existing_hosts() {
    local repo_dir="${1:-$HOME/.config/nixpkgs}"
    local flake_file="$repo_dir/flake.nix"

    if [ ! -f "$flake_file" ]; then
        return
    fi

    # Extract host names from darwinConfigurations (exclude example configs)
    grep -E '^\s+"[a-zA-Z0-9_-]+" = mkDarwinSystem' "$flake_file" | \
        sed -E 's/.*"([^"]+)".*/\1/' | \
        grep -v -E '^(work-macbook|personal-macbook|minimal-mac|home-studio)' | \
        sort -u
}

# Function to get host details for display
get_host_info() {
    local repo_dir="$1"
    local hostname="$2"
    local flake_file="$repo_dir/flake.nix"

    # Extract machine type
    local config_block=""
    local in_block=0
    local brace_count=0

    while IFS= read -r line; do
        if [ $in_block -eq 0 ]; then
            if echo "$line" | grep -q "\"$hostname\" = mkDarwinSystem"; then
                in_block=1
                brace_count=0
            fi
        fi
        if [ $in_block -eq 1 ]; then
            config_block="${config_block}${line}"$'\n'
            local open=$(echo "$line" | tr -cd '{' | wc -c)
            local close=$(echo "$line" | tr -cd '}' | wc -c)
            brace_count=$((brace_count + open - close))
            if [ $brace_count -le 0 ] && [ -n "$config_block" ]; then
                break
            fi
        fi
    done < "$flake_file"

    local machine_type=$(echo "$config_block" | sed -n 's/.*machineType *= *"\([^"]*\)".*/\1/p' | head -1)
    local profiles=$(echo "$config_block" | grep -o './hosts/profiles/[^"]*\.nix' | sed 's|.*/||; s|\.nix||' | tr '\n' ' ' | sed 's/ $//')

    echo "$machine_type|$profiles"
}

# Main wizard function
run_setup_wizard() {
    local repo_dir="${1:-$HOME/.config/nixpkgs}"

    print_header "nix-me Setup Wizard"
    echo ""

    # Step 1: Select existing config or create new
    print_info "Choose a configuration:"
    echo ""

    local hosts_list=$(get_existing_hosts "$repo_dir")
    local i=1
    local host_array=""

    # Show existing hosts
    for host in $hosts_list; do
        local info=$(get_host_info "$repo_dir" "$host")
        local mtype=$(echo "$info" | cut -d'|' -f1)
        local profs=$(echo "$info" | cut -d'|' -f2)

        if [ -z "$profs" ]; then
            profs="minimal"
        fi

        printf "  ${CYAN}%d${NC}) %-20s [%s] %s\n" "$i" "$host" "$mtype" "$profs"
        host_array="$host_array $host"
        i=$((i + 1))
    done
    host_array=$(echo "$host_array" | sed 's/^ //')

    local host_count=$((i - 1))
    local new_option=$i

    echo ""
    echo "  ${CYAN}${new_option}${NC}) Create new configuration..."
    echo ""

    read -p "$(echo -e ${CYAN}Select [1]: ${NC})" choice
    choice=${choice:-1}

    if [ "$choice" = "$new_option" ]; then
        # Create new configuration
        create_new_configuration "$repo_dir"
    elif [ -n "$choice" ] && [ "$choice" -ge 1 ] 2>/dev/null && [ "$choice" -le "$host_count" ] 2>/dev/null; then
        # Selected existing host
        WIZARD_SELECTED_HOST=$(echo "$host_array" | cut -d' ' -f"$choice")
        select_existing_host "$repo_dir" "$WIZARD_SELECTED_HOST"
    else
        print_warn "Invalid selection, using first option"
        WIZARD_SELECTED_HOST=$(echo "$host_array" | cut -d' ' -f1)
        select_existing_host "$repo_dir" "$WIZARD_SELECTED_HOST"
    fi

    return $?
}

# Select an existing pre-made host
select_existing_host() {
    local repo_dir="$1"
    local hostname="$2"

    local info=$(get_host_info "$repo_dir" "$hostname")
    local mtype=$(echo "$info" | cut -d'|' -f1)
    local profs=$(echo "$info" | cut -d'|' -f2)

    WIZARD_HOSTNAME="$hostname"
    WIZARD_MACHINE_TYPE="$mtype"
    WIZARD_PROFILES="$profs"

    echo ""
    print_success "Selected: $hostname"
    echo ""
    echo "  Machine type: $mtype"
    echo "  Profiles:     ${profs:-minimal}"
    echo ""

    # Get username
    local default_user=$(whoami)
    read -p "$(echo -e ${CYAN}Username [${default_user}]: ${NC})" input_user
    WIZARD_USERNAME=${input_user:-$default_user}

    # Ask about customizations
    echo ""
    if ask_yes_no "Would you like to customize packages?" "n"; then
        customize_packages "$repo_dir" "$hostname"
    fi

    # Summary and confirm
    show_summary_and_confirm "$repo_dir"
}

# Create a new configuration from scratch
create_new_configuration() {
    local repo_dir="$1"

    print_header "Create New Configuration"
    echo ""

    # Hostname
    local default_hostname=$(hostname -s 2>/dev/null | tr '[:upper:]' '[:lower:]' || echo "my-mac")
    read -p "$(echo -e ${CYAN}Hostname [${default_hostname}]: ${NC})" input_hostname
    WIZARD_HOSTNAME=${input_hostname:-$default_hostname}

    # Machine type
    echo ""
    print_header "Machine Type"
    echo ""
    echo "  ${CYAN}1${NC}) macbook     - MacBook Air/Pro (battery optimized)"
    echo "  ${CYAN}2${NC}) macbook-pro - MacBook Pro (performance focused)"
    echo "  ${CYAN}3${NC}) macmini     - Mac Mini (desktop, multi-display)"
    echo "  ${CYAN}4${NC}) vm          - Virtual Machine (minimal)"
    echo ""

    read -p "$(echo -e ${CYAN}Select [1]: ${NC})" type_choice
    type_choice=${type_choice:-1}

    case "$type_choice" in
        1) WIZARD_MACHINE_TYPE="macbook" ;;
        2) WIZARD_MACHINE_TYPE="macbook-pro" ;;
        3) WIZARD_MACHINE_TYPE="macmini" ;;
        4) WIZARD_MACHINE_TYPE="vm" ;;
        *) WIZARD_MACHINE_TYPE="macbook" ;;
    esac
    print_success "Selected: $WIZARD_MACHINE_TYPE"

    # Profiles
    echo ""
    print_header "Profiles"
    echo ""
    print_info "Select which profiles to include:"
    echo ""

    WIZARD_PROFILES=""

    echo "  ${CYAN}dev${NC} - Development tools (VS Code, Node, Python, Go, Docker...)"
    if ask_yes_no "  Include?" "y"; then
        WIZARD_PROFILES="dev"
    fi

    echo ""
    echo "  ${CYAN}work${NC} - Work apps (Slack, Teams, Zoom, Office...)"
    if ask_yes_no "  Include?" "y"; then
        [ -n "$WIZARD_PROFILES" ] && WIZARD_PROFILES="$WIZARD_PROFILES work" || WIZARD_PROFILES="work"
    fi

    echo ""
    echo "  ${CYAN}personal${NC} - Personal apps (Spotify, OBS, media tools...)"
    if ask_yes_no "  Include?" "n"; then
        [ -n "$WIZARD_PROFILES" ] && WIZARD_PROFILES="$WIZARD_PROFILES personal" || WIZARD_PROFILES="personal"
    fi

    # Display name
    echo ""
    local default_name="$WIZARD_HOSTNAME"
    read -p "$(echo -e ${CYAN}Display Name [${default_name}]: ${NC})" input_name
    WIZARD_MACHINE_NAME=${input_name:-$default_name}

    # Username
    local default_user=$(whoami)
    read -p "$(echo -e ${CYAN}Username [${default_user}]: ${NC})" input_user
    WIZARD_USERNAME=${input_user:-$default_user}

    # Ask about customizations
    echo ""
    if ask_yes_no "Would you like to customize packages?" "n"; then
        customize_packages "$repo_dir" "$WIZARD_HOSTNAME"
    fi

    # Summary and confirm
    show_summary_and_confirm "$repo_dir"
}

# Customize packages
customize_packages() {
    local repo_dir="$1"
    local hostname="$2"

    print_header "Package Customization"
    echo ""
    print_info "You can add or remove packages from the base configuration."
    echo ""

    # Add GUI apps
    echo "  ${CYAN}Add GUI apps (Homebrew casks)${NC}"
    echo "  Examples: figma, notion, discord, steam"
    read -p "  Apps to add (comma-separated, or Enter to skip): " add_casks

    # Remove GUI apps
    echo ""
    echo "  ${CYAN}Remove GUI apps${NC}"
    echo "  Examples: spotify, slack"
    read -p "  Apps to remove (comma-separated, or Enter to skip): " remove_casks

    # Add CLI tools
    echo ""
    echo "  ${CYAN}Add CLI tools (Nix packages)${NC}"
    echo "  Examples: wget, tmux, neovim"
    read -p "  Tools to add (comma-separated, or Enter to skip): " add_tools

    # Store customizations for later
    WIZARD_ADD_CASKS="$add_casks"
    WIZARD_REMOVE_CASKS="$remove_casks"
    WIZARD_ADD_TOOLS="$add_tools"

    if [ -n "$add_casks" ] || [ -n "$remove_casks" ] || [ -n "$add_tools" ]; then
        echo ""
        print_success "Customizations saved"
    fi
}

# Show summary and confirm
show_summary_and_confirm() {
    local repo_dir="$1"

    echo ""
    print_header "Configuration Summary"
    echo ""
    echo "  Hostname:      $WIZARD_HOSTNAME"
    echo "  Machine Type:  $WIZARD_MACHINE_TYPE"
    [ -n "$WIZARD_MACHINE_NAME" ] && echo "  Display Name:  $WIZARD_MACHINE_NAME"
    echo "  Username:      $WIZARD_USERNAME"
    echo "  Profiles:      ${WIZARD_PROFILES:-minimal}"

    if [ -n "$WIZARD_ADD_CASKS" ] || [ -n "$WIZARD_REMOVE_CASKS" ] || [ -n "$WIZARD_ADD_TOOLS" ]; then
        echo ""
        echo "  Customizations:"
        [ -n "$WIZARD_ADD_CASKS" ] && echo "    + Apps:  $WIZARD_ADD_CASKS"
        [ -n "$WIZARD_REMOVE_CASKS" ] && echo "    - Apps:  $WIZARD_REMOVE_CASKS"
        [ -n "$WIZARD_ADD_TOOLS" ] && echo "    + Tools: $WIZARD_ADD_TOOLS"
    fi
    echo ""

    if ! ask_yes_no "Proceed with this configuration?"; then
        print_error "Setup cancelled"
        WIZARD_SUCCESS=0
        return 1
    fi

    # Generate configuration if creating new
    if [ -z "$WIZARD_SELECTED_HOST" ]; then
        echo ""
        print_info "Generating configuration..."

        if [ -f "$repo_dir/lib/config-builder.sh" ]; then
            source "$repo_dir/lib/config-builder.sh"
            generate_machine_config_multi_profile \
                "$WIZARD_HOSTNAME" \
                "$WIZARD_MACHINE_TYPE" \
                "${WIZARD_MACHINE_NAME:-$WIZARD_HOSTNAME}" \
                "$WIZARD_USERNAME" \
                "$repo_dir" \
                $WIZARD_PROFILES
        fi
    fi

    # Apply customizations if any
    if [ -n "$WIZARD_ADD_CASKS" ] || [ -n "$WIZARD_REMOVE_CASKS" ] || [ -n "$WIZARD_ADD_TOOLS" ]; then
        apply_customizations "$repo_dir" "$WIZARD_HOSTNAME"
    fi

    WIZARD_SUCCESS=1
    return 0
}

# Apply package customizations to host config
apply_customizations() {
    local repo_dir="$1"
    local hostname="$2"
    local host_config="$repo_dir/hosts/machines/$hostname/default.nix"

    # Create host directory if it doesn't exist
    mkdir -p "$(dirname "$host_config")"

    if [ ! -f "$host_config" ]; then
        # Create basic host config
        cat > "$host_config" << EOF
{ pkgs, config, lib, ... }:

{
  imports = [
    ../../types/${WIZARD_MACHINE_TYPE}/default.nix
  ];

  apps = {
    useBaseLists = true;
EOF
    else
        # File exists, we'd need to modify it
        print_info "Host config exists, customizations noted but may need manual editing"
        return
    fi

    # Add casks
    if [ -n "$WIZARD_ADD_CASKS" ]; then
        echo "" >> "$host_config"
        echo "    casksToAdd = [" >> "$host_config"
        IFS=',' read -ra casks <<< "$WIZARD_ADD_CASKS"
        for cask in "${casks[@]}"; do
            cask=$(echo "$cask" | tr -d ' ')
            echo "      \"$cask\"" >> "$host_config"
        done
        echo "    ];" >> "$host_config"
    fi

    # Remove casks
    if [ -n "$WIZARD_REMOVE_CASKS" ]; then
        echo "" >> "$host_config"
        echo "    casksToRemove = [" >> "$host_config"
        IFS=',' read -ra casks <<< "$WIZARD_REMOVE_CASKS"
        for cask in "${casks[@]}"; do
            cask=$(echo "$cask" | tr -d ' ')
            echo "      \"$cask\"" >> "$host_config"
        done
        echo "    ];" >> "$host_config"
    fi

    # Add tools
    if [ -n "$WIZARD_ADD_TOOLS" ]; then
        echo "" >> "$host_config"
        echo "    systemPackagesToAdd = [" >> "$host_config"
        IFS=',' read -ra tools <<< "$WIZARD_ADD_TOOLS"
        for tool in "${tools[@]}"; do
            tool=$(echo "$tool" | tr -d ' ')
            echo "      \"$tool\"" >> "$host_config"
        done
        echo "    ];" >> "$host_config"
    fi

    # Close the config
    cat >> "$host_config" << EOF
  };
}
EOF

    print_success "Created host config: $host_config"
}

# Export for use by install.sh
export -f run_setup_wizard 2>/dev/null || true
