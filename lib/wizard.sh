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
GREEN='\033[0;32m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

# Arrow key selector function
# Usage: select_option "Option 1" "Option 2" "Option 3"
# Returns: selected index (0-based) in SELECTED_INDEX
select_option() {
    local options=("$@")
    local count=${#options[@]}
    local selected=0
    local key=""
    local first_draw=1

    # Hide cursor
    printf "\033[?25l"

    # Trap to restore cursor on exit
    trap 'printf "\033[?25h"' RETURN

    # Draw function
    draw_options() {
        for i in "${!options[@]}"; do
            if [ $i -eq $selected ]; then
                printf "  ${GREEN}❯${NC} ${BOLD}%s${NC}\033[K\n" "${options[$i]}"
            else
                printf "    ${DIM}%s${NC}\033[K\n" "${options[$i]}"
            fi
        done
    }

    # Initial draw
    draw_options

    while true; do
        # Read single keypress
        IFS= read -rsn1 key

        local old_selected=$selected

        # Handle arrow keys (escape sequences)
        if [ "$key" = $'\x1b' ]; then
            read -rsn2 key
            case "$key" in
                '[A') # Up arrow
                    ((selected--))
                    [ $selected -lt 0 ] && selected=$((count - 1))
                    ;;
                '[B') # Down arrow
                    ((selected++))
                    [ $selected -ge $count ] && selected=0
                    ;;
            esac
        elif [ "$key" = "" ]; then
            # Enter pressed
            break
        elif [ "$key" = "k" ] || [ "$key" = "K" ]; then
            ((selected--))
            [ $selected -lt 0 ] && selected=$((count - 1))
        elif [ "$key" = "j" ] || [ "$key" = "J" ]; then
            ((selected++))
            [ $selected -ge $count ] && selected=0
        fi

        # Only redraw if selection changed
        if [ $selected -ne $old_selected ]; then
            # Move cursor up to start of options
            printf "\033[${count}A"
            draw_options
        fi
    done

    # Show cursor
    printf "\033[?25h"

    SELECTED_INDEX=$selected
    return $selected
}

# Checkbox selector for multiple selection
# Usage: select_multiple "Option 1" "Option 2" "Option 3"
# Returns: space-separated indices in SELECTED_INDICES
select_multiple() {
    local options=("$@")
    local count=${#options[@]}
    local selected=0
    local key=""
    local checked=""

    # Initialize all unchecked
    for i in "${!options[@]}"; do
        checked="$checked 0"
    done
    checked=$(echo "$checked" | sed 's/^ //')

    # Hide cursor
    printf "\033[?25l"
    trap 'printf "\033[?25h"' RETURN

    # Draw function
    draw_checkboxes() {
        for i in "${!options[@]}"; do
            local is_checked=$(echo "$checked" | cut -d' ' -f$((i + 1)))
            local checkbox="○"
            [ "$is_checked" = "1" ] && checkbox="${GREEN}●${NC}"

            if [ $i -eq $selected ]; then
                printf "  ${GREEN}❯${NC} %b ${BOLD}%s${NC}\033[K\n" "$checkbox" "${options[$i]}"
            else
                printf "    %b ${DIM}%s${NC}\033[K\n" "$checkbox" "${options[$i]}"
            fi
        done
    }

    # Initial draw
    draw_checkboxes

    while true; do
        # Read keypress
        IFS= read -rsn1 key

        local needs_redraw=0

        if [ "$key" = $'\x1b' ]; then
            read -rsn2 key
            case "$key" in
                '[A') ((selected--)); [ $selected -lt 0 ] && selected=$((count - 1)); needs_redraw=1 ;;
                '[B') ((selected++)); [ $selected -ge $count ] && selected=0; needs_redraw=1 ;;
            esac
        elif [ "$key" = "" ]; then
            # Enter - finish selection
            break
        elif [ "$key" = " " ]; then
            # Space - toggle current option
            local new_checked=""
            for i in "${!options[@]}"; do
                local is_checked=$(echo "$checked" | cut -d' ' -f$((i + 1)))
                if [ $i -eq $selected ]; then
                    [ "$is_checked" = "1" ] && is_checked="0" || is_checked="1"
                fi
                new_checked="$new_checked $is_checked"
            done
            checked=$(echo "$new_checked" | sed 's/^ //')
            needs_redraw=1
        elif [ "$key" = "k" ]; then
            ((selected--)); [ $selected -lt 0 ] && selected=$((count - 1)); needs_redraw=1
        elif [ "$key" = "j" ]; then
            ((selected++)); [ $selected -ge $count ] && selected=0; needs_redraw=1
        fi

        if [ $needs_redraw -eq 1 ]; then
            printf "\033[${count}A"
            draw_checkboxes
        fi
    done

    printf "\033[?25h"

    # Build result
    SELECTED_INDICES=""
    for i in "${!options[@]}"; do
        local is_checked=$(echo "$checked" | cut -d' ' -f$((i + 1)))
        if [ "$is_checked" = "1" ]; then
            SELECTED_INDICES="$SELECTED_INDICES $i"
        fi
    done
    SELECTED_INDICES=$(echo "$SELECTED_INDICES" | sed 's/^ //')
}

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
    print_info "Use ↑↓ arrows to navigate, Enter to select"
    echo ""

    # Build options list
    local hosts_list=$(get_existing_hosts "$repo_dir")
    local options=""
    local host_array=""
    local i=0

    for host in $hosts_list; do
        local info=$(get_host_info "$repo_dir" "$host")
        local mtype=$(echo "$info" | cut -d'|' -f1)
        local profs=$(echo "$info" | cut -d'|' -f2)
        [ -z "$profs" ] && profs="minimal"

        # Build display string
        local display=$(printf "%-18s  [%-11s]  %s" "$host" "$mtype" "$profs")
        options="$options|$display"
        host_array="$host_array $host"
        i=$((i + 1))
    done
    options="$options|➕ Create new configuration..."
    options=$(echo "$options" | sed 's/^|//')
    host_array=$(echo "$host_array" | sed 's/^ //')

    local host_count=$i

    # Convert to array and select
    IFS='|' read -ra opt_array <<< "$options"
    select_option "${opt_array[@]}"

    if [ $SELECTED_INDEX -eq $host_count ]; then
        # Create new configuration
        create_new_configuration "$repo_dir"
    else
        # Selected existing host
        local idx=$((SELECTED_INDEX + 1))
        WIZARD_SELECTED_HOST=$(echo "$host_array" | cut -d' ' -f$idx)
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
    print_info "Use ↑↓ to navigate, Enter to select"
    echo ""

    local machine_types=(
        "macbook      MacBook Air/Pro (battery optimized)"
        "macbook-pro  MacBook Pro (performance focused)"
        "macmini      Mac Mini (desktop, multi-display)"
        "vm           Virtual Machine (minimal)"
    )
    select_option "${machine_types[@]}"

    case $SELECTED_INDEX in
        0) WIZARD_MACHINE_TYPE="macbook" ;;
        1) WIZARD_MACHINE_TYPE="macbook-pro" ;;
        2) WIZARD_MACHINE_TYPE="macmini" ;;
        3) WIZARD_MACHINE_TYPE="vm" ;;
    esac
    print_success "Selected: $WIZARD_MACHINE_TYPE"

    # Profiles
    echo ""
    print_header "Profiles"
    print_info "Use ↑↓ to navigate, Space to toggle, Enter to confirm"
    echo ""

    local profile_options=(
        "dev       Development tools (VS Code, Node, Python, Docker...)"
        "work      Work apps (Slack, Teams, Zoom, Office...)"
        "personal  Personal apps (Spotify, OBS, media tools...)"
    )
    select_multiple "${profile_options[@]}"

    WIZARD_PROFILES=""
    for idx in $SELECTED_INDICES; do
        case $idx in
            0) [ -n "$WIZARD_PROFILES" ] && WIZARD_PROFILES="$WIZARD_PROFILES dev" || WIZARD_PROFILES="dev" ;;
            1) [ -n "$WIZARD_PROFILES" ] && WIZARD_PROFILES="$WIZARD_PROFILES work" || WIZARD_PROFILES="work" ;;
            2) [ -n "$WIZARD_PROFILES" ] && WIZARD_PROFILES="$WIZARD_PROFILES personal" || WIZARD_PROFILES="personal" ;;
        esac
    done

    if [ -n "$WIZARD_PROFILES" ]; then
        print_success "Selected: $WIZARD_PROFILES"
    else
        print_info "No profiles selected (minimal base)"
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
