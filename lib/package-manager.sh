#!/bin/bash

# Interactive package management with fzf

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/ui.sh"

CONFIG_DIR="${HOME}/.config/nixpkgs"

# Ensure Homebrew is in PATH
if [[ -f /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -f /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi

# Check if fzf is available
has_fzf() {
    command -v fzf &>/dev/null
}

# Check if gum is available (alternative fancy CLI tool)
has_gum() {
    command -v gum &>/dev/null
}

# Search Homebrew casks with descriptions
search_homebrew_casks() {
    local query="${1:-}"

    print_info "Searching Homebrew casks..."

    # Get all casks with descriptions
    local results=$(brew search --casks "$query" 2>/dev/null | grep -v "^==")

    if [ -z "$results" ]; then
        return 1
    fi

    echo "$results"
}

# Get cask description
get_cask_description() {
    local cask="$1"
    brew info --cask "$cask" 2>/dev/null | head -2 | tail -1 | sed 's/^[[:space:]]*//'
}

# Interactive cask browser with fzf
browse_homebrew_casks_fzf() {
    local query="${1:-}"

    if ! has_fzf; then
        print_error "fzf is not installed. Install it with: brew install fzf"
        return 1
    fi

    print_header "Browse Homebrew Applications"
    print_info "Searching for applications..."
    echo ""

    # Get list of installed casks
    local installed_casks=$(brew list --cask 2>/dev/null | sort)

    # Create temp file with cask list
    local temp_file=$(mktemp)
    local formatted_file=$(mktemp)

    # Get all casks (or search results)
    if [ -n "$query" ]; then
        brew search --casks "$query" 2>/dev/null | grep -v "^==" > "$temp_file"
    else
        print_info "Loading popular applications (this may take a moment)..."
        # Get popular casks
        cat > "$temp_file" << 'EOF'
visual-studio-code
docker
google-chrome
firefox
spotify
slack
zoom
discord
notion
obsidian
postman
iterm2
rectangle
raycast
1password
alfred
tableplus
sequel-ace
fork
github
insomnia
figma
sketch
vlc
obs
handbrake
transmission
calibre
gimp
inkscape
blender
audacity
steam
epic-games
minecraft
tunnelblick
protonvpn
nordvpn
expressvpn
little-snitch
micro-snitch
bartender
cleanmymac
daisy-disk
the-unarchiver
keka
appcleaner
alfred
hammerspoon
karabiner-elements
bettertouchtool
stats
istat-menus
monitorcontrol
displaylink
EOF
    fi

    if [ ! -s "$temp_file" ]; then
        rm "$temp_file"
        print_error "No applications found"
        return 1
    fi

    # Format casks with green tick for installed packages
    while IFS= read -r cask; do
        if echo "$installed_casks" | grep -q "^${cask}$"; then
            # Installed - add green tick
            echo -e "\033[0;32m✓\033[0m $cask" >> "$formatted_file"
        else
            # Not installed - add spacing
            echo "  $cask" >> "$formatted_file"
        fi
    done < "$temp_file"

    # Use fzf for selection with preview
    print_info "Use arrow keys to browse, TAB to select multiple, ENTER to confirm"
    print_info "Green tick (✓) indicates already installed packages"
    print_info "Press Ctrl-S to search for different packages"
    echo ""

    # Create a search script for reload functionality
    local search_script=$(mktemp)
    cat > "$search_script" << 'SEARCHEOF'
#!/bin/bash
query="$1"
installed_casks=$(brew list --cask 2>/dev/null | sort)
if [ -n "$query" ]; then
    brew search --casks "$query" 2>/dev/null | grep -v "^==" | while IFS= read -r cask; do
        if echo "$installed_casks" | grep -q "^${cask}$"; then
            echo -e "\033[0;32m✓\033[0m $cask"
        else
            echo "  $cask"
        fi
    done
fi
SEARCHEOF
    chmod +x "$search_script"

    local selected=$(cat "$formatted_file" | fzf \
        --multi \
        --height=80% \
        --border=rounded \
        --prompt="Select apps > " \
        --header="✓ = installed | TAB: select multiple | ENTER: confirm | Ctrl-S: search | ESC: cancel" \
        --preview="brew info --cask \$(echo {} | awk '{print \$NF}') 2>/dev/null | head -10" \
        --preview-window=right:50%:wrap \
        --bind="ctrl-a:select-all,ctrl-d:deselect-all" \
        --bind="ctrl-s:reload($search_script {q})" \
        --color="header:italic:cyan" \
        --ansi \
    )

    rm -f "$search_script"

    rm "$temp_file"
    rm "$formatted_file"

    if [ -z "$selected" ]; then
        print_info "No selection made"
        return 0
    fi

    # Extract package names from formatted lines (remove tick/spacing prefix)
    local cleaned_selected=$(echo "$selected" | sed 's/^[[:space:]]*✓[[:space:]]*//' | sed 's/^[[:space:]]*//')

    # Return selected apps
    echo "$cleaned_selected"
}

# Interactive cask browser without fzf (fallback)
browse_homebrew_casks_simple() {
    local query="${1:-}"

    print_header "Browse Homebrew Applications"
    print_info "Searching for: ${query:-all popular apps}"
    echo ""

    # Get list of installed casks
    local installed_casks=$(brew list --cask 2>/dev/null | sort)

    local results=$(search_homebrew_casks "$query")

    if [ -z "$results" ]; then
        print_error "No applications found"
        return 1
    fi

    # Display results
    local apps_array=()
    local index=1

    while IFS= read -r cask; do
        if [ -n "$cask" ]; then
            apps_array+=("$cask")
            # Check if installed and show green tick
            if echo "$installed_casks" | grep -q "^${cask}$"; then
                echo -e "  ${CYAN}${index}${NC}) ${GREEN}✓${NC} $cask"
            else
                echo "  ${CYAN}${index}${NC})   $cask"
            fi
            ((index++))
        fi
    done <<< "$results"

    echo ""
    echo "  ${CYAN}A${NC}) Select all"
    echo "  ${CYAN}0${NC}) Cancel"
    echo ""

    read -p "Select applications (comma-separated numbers or A for all): " selection

    if [ "$selection" == "0" ] || [ -z "$selection" ]; then
        print_info "Cancelled"
        return 0
    fi

    # Handle "select all"
    if [[ "$selection" =~ ^[Aa]$ ]]; then
        for app in "${apps_array[@]}"; do
            echo "$app"
        done
        return 0
    fi

    # Parse comma-separated selections
    IFS=',' read -ra selections <<< "$selection"
    for sel in "${selections[@]}"; do
        sel=$(echo "$sel" | tr -d ' ')
        if [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -ge 1 ] && [ "$sel" -le "${#apps_array[@]}" ]; then
            echo "${apps_array[$((sel-1))]}"
        fi
    done
}

# Add selected casks to configuration
add_casks_to_config() {
    local hostname="${1:-$(hostname -s | tr '[:upper:]' '[:lower:]')}"
    shift
    local casks=("$@")

    if [ ${#casks[@]} -eq 0 ]; then
        print_warn "No casks to add"
        return 0
    fi

    print_header "Adding Applications to Configuration"
    print_info "Target machine: $hostname"
    echo ""

    # Determine config file
    local host_config="$CONFIG_DIR/hosts/$hostname/default.nix"
    local installations_config="$CONFIG_DIR/modules/darwin/apps/installations.nix"

    # Choose where to add
    echo "Where should these apps be added?"
    echo ""
    echo "  ${CYAN}1${NC}) Host-specific config (hosts/$hostname/default.nix)"
    echo "  ${CYAN}2${NC}) Base configuration (modules/darwin/apps/installations.nix)"
    echo ""

    read -p "Choice [1]: " choice
    choice=${choice:-1}

    local target_file
    case $choice in
        1) target_file="$host_config" ;;
        2) target_file="$installations_config" ;;
        *)
            print_error "Invalid choice"
            return 1
            ;;
    esac

    if [ ! -f "$target_file" ]; then
        print_error "Configuration file not found: $target_file"
        return 1
    fi

    print_info "Apps to add:"
    for cask in "${casks[@]}"; do
        echo "  ${GREEN}•${NC} $cask"
    done
    echo ""

    if ! ask_yes_no "Add these apps to $target_file?" "y"; then
        print_info "Cancelled"
        return 0
    fi

    # Backup config file
    cp "$target_file" "$target_file.backup"
    print_info "Created backup: $target_file.backup"

    # Add casks to casksToAdd array
    print_info "Updating configuration file..."

    # Check if casksToAdd exists
    if grep -q "casksToAdd = \[" "$target_file"; then
        # Find the casksToAdd array and add before the closing bracket
        local temp_file=$(mktemp)
        local in_casks_array=0

        while IFS= read -r line; do
            echo "$line"

            # Detect if we're in the casksToAdd array
            if [[ "$line" =~ casksToAdd[[:space:]]*=[[:space:]]*\[ ]]; then
                in_casks_array=1
            fi

            # If we find the closing bracket while in array, add our casks before it
            if [ $in_casks_array -eq 1 ] && [[ "$line" =~ ^[[:space:]]*\]\; ]]; then
                for cask in "${casks[@]}"; do
                    echo "      \"$cask\""
                done
                in_casks_array=0
            fi
        done < "$target_file" > "$temp_file"

        mv "$temp_file" "$target_file"
    else
        # casksToAdd doesn't exist, need to add it
        print_warn "casksToAdd array not found in config"
        print_info "Please manually add these apps to: $target_file"
        for cask in "${casks[@]}"; do
            echo "  \"$cask\""
        done
        return 1
    fi

    print_success "Configuration updated!"
    echo ""

    if ask_yes_no "Apply changes now?" "y"; then
        return 2  # Signal to apply changes
    else
        print_info "Run 'nix-me switch' to apply changes later"
        return 0
    fi
}

# Search Nix packages (basic search)
search_nix_packages() {
    local query="$1"

    print_info "Searching Nix packages for: $query"

    # Use nix search
    nix search nixpkgs "$query" --json 2>/dev/null | \
        jq -r 'to_entries[] | "\(.key | split(".")[1])"' | \
        head -50
}

# Browse popular categories
browse_by_category() {
    if ! has_fzf; then
        print_error "fzf is required for category browsing"
        return 1
    fi

    print_header "Browse Applications by Category"
    echo ""

    local categories=(
        "Development:Visual Studio Code, Docker, Git clients, IDEs"
        "Productivity:Notion, Obsidian, Todoist, Calendar apps"
        "Communication:Slack, Discord, Zoom, Microsoft Teams"
        "Design:Figma, Sketch, Adobe Creative Cloud"
        "Browsers:Chrome, Firefox, Brave, Arc"
        "Media:Spotify, VLC, OBS, Handbrake"
        "Utilities:Rectangle, Raycast, Alfred, CleanMyMac"
        "Security:1Password, Little Snitch, VPN clients"
        "Databases:TablePlus, Sequel Ace, DBeaver"
    )

    local selected_category=$(printf '%s\n' "${categories[@]}" | \
        fzf --height=50% \
            --border=rounded \
            --prompt="Select category > " \
            --header="Choose a category to browse" \
            --delimiter=":" \
            --with-nth=1 \
            --preview='echo {2}' \
            --preview-window=down:3:wrap
    )

    if [ -z "$selected_category" ]; then
        return 0
    fi

    # Extract category name
    local category_name=$(echo "$selected_category" | cut -d: -f1)

    # Show category-specific apps
    case "$category_name" in
        "Development")
            browse_homebrew_casks_fzf "code docker postman tableplus"
            ;;
        "Productivity")
            browse_homebrew_casks_fzf "notion obsidian todoist"
            ;;
        "Communication")
            browse_homebrew_casks_fzf "slack discord zoom teams"
            ;;
        "Design")
            browse_homebrew_casks_fzf "figma sketch adobe"
            ;;
        "Browsers")
            browse_homebrew_casks_fzf "chrome firefox brave arc"
            ;;
        "Media")
            browse_homebrew_casks_fzf "spotify vlc obs"
            ;;
        "Utilities")
            browse_homebrew_casks_fzf "rectangle raycast alfred"
            ;;
        "Security")
            browse_homebrew_casks_fzf "1password vpn"
            ;;
        "Databases")
            browse_homebrew_casks_fzf "tableplus sequel"
            ;;
    esac
}

# Export functions
export -f search_homebrew_casks
export -f browse_homebrew_casks_fzf
export -f browse_homebrew_casks_simple
export -f add_casks_to_config
export -f browse_by_category
