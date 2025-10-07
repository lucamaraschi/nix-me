#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Fallback UI functions (used before repo is cloned)
print_header() { echo ""; echo "=== $1 ==="; echo ""; }
print_success() { echo "✓ $1"; }
print_error() { echo "✗ $1"; }
print_info() { echo "• $1"; }
print_warn() { echo "⚠ $1"; }
print_step() { echo "[$1] $2"; }
ask_yes_no() { read -p "$1 (Y/n): " answer; [[ -z $answer || $answer =~ ^[Yy] ]]; }

main() {
    # Control variables
    FORCE_NIX_REINSTALL=${FORCE_NIX_REINSTALL:-0}
    NON_INTERACTIVE=${NON_INTERACTIVE:-0}
    USE_WIZARD=${USE_WIZARD:-1}

    REPO_URL=${REPO_URL:-"https://github.com/lucamaraschi/nix-me.git"}
    REPO_BRANCH=${REPO_BRANCH:-"main"}
    REPO_DIR=${HOME}/.config/nixpkgs

    print_header "nix-me Installation"
    echo ""

    # Verify macOS
    if [[ "$OSTYPE" != "darwin"* ]]; then
        print_error "This script must be run on macOS"
        exit 1
    fi

    # STEP 1: Run wizard FIRST (if appropriate) - before cloning repo
    if [ $# -eq 0 ] && [ "$NON_INTERACTIVE" != "1" ] && [ "$USE_WIZARD" == "1" ]; then
        # Try to use wizard from existing repo if available
        if [ -f "$REPO_DIR/lib/wizard.sh" ]; then
            source "$REPO_DIR/lib/ui.sh" 2>/dev/null || true
            source "$REPO_DIR/lib/wizard.sh"

            if run_setup_wizard "$REPO_DIR" && [ "$WIZARD_SUCCESS" == "1" ]; then
                # Check if we're just modifying an existing machine
                if [ "${WIZARD_MODIFY_ONLY:-0}" == "1" ]; then
                    print_success "Configuration updated for: $WIZARD_HOSTNAME"
                    echo ""
                    print_info "Run 'make switch' to apply changes"
                    exit 0
                fi

                # Use wizard values for new machine
                HOST_NAME=${WIZARD_HOSTNAME}
                MACHINE_TYPE=${WIZARD_MACHINE_TYPE}
                MACHINE_NAME=${WIZARD_MACHINE_NAME}
                NIXOS_USERNAME=${WIZARD_USERNAME}
                CONFIG_PROFILE=${WIZARD_CONFIG_PROFILE:-standard}
            else
                print_error "Setup cancelled"
                exit 1
            fi
        else
            print_warn "Wizard not available (first-time installation)"
            print_info "Using default configuration values"
            HOST_NAME=$(hostname -s | tr '[:upper:]' '[:lower:]')
            MACHINE_TYPE="macbook"
            MACHINE_NAME="$HOST_NAME"
            NIXOS_USERNAME=$(whoami)
            CONFIG_PROFILE="standard"
        fi
    else
        # Command-line arguments
        HOST_NAME=${1:-$(hostname -s | tr '[:upper:]' '[:lower:]')}
        MACHINE_TYPE=${2:-"macbook"}
        MACHINE_NAME=${3:-"$HOST_NAME"}
        NIXOS_USERNAME=${4:-$(whoami)}
        CONFIG_PROFILE=${5:-standard}
    fi

    # Display configuration
    print_header "Installation Configuration"
    echo ""
    echo "  Hostname:       $HOST_NAME"
    echo "  Machine Type:   $MACHINE_TYPE"
    echo "  Machine Name:   $MACHINE_NAME"
    echo "  Username:       $NIXOS_USERNAME"
    echo "  Profile:        $CONFIG_PROFILE"
    echo "  Repository:     $REPO_URL"
    echo "  Branch:         $REPO_BRANCH"
    echo ""

    if [ "$NON_INTERACTIVE" != "1" ]; then
        if ! ask_yes_no "Continue with installation?"; then
            print_error "Installation cancelled"
            exit 1
        fi
    fi

    # STEP 2: Request sudo privileges
    print_step "1/6" "Requesting Administrator Privileges"
    sudo -v || { print_error "Authentication failed"; exit 1; }

    # Sudo refresh background process
    ( while true; do sudo -v; sleep 60; done ) &
    SUDO_REFRESH_PID=$!
    trap "kill $SUDO_REFRESH_PID 2>/dev/null || true" EXIT

    print_success "Administrator access granted"
    echo ""

    # STEP 3: Install Xcode CLI tools
    print_step "2/6" "Installing Xcode Command Line Tools"
    if [[ -z "$(command -v git)" ]]; then
        print_info "Installing Xcode Command Line Tools..."
        xcode-select --install &> /dev/null
        print_info "Waiting for installation to complete..."
        until xcode-select --print-path &> /dev/null; do sleep 5; done
    fi
    print_success "Xcode Command Line Tools ready"
    echo ""

    # STEP 4: Install Nix
    print_step "3/6" "Installing Nix Package Manager"
    if ! command -v nix &>/dev/null || [ "$FORCE_NIX_REINSTALL" == "1" ]; then
        print_info "Installing Nix (this may take 5-10 minutes)..."
        curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install

        # Source Nix environment
        if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
            source '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
        fi
    fi
    export PATH=$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$PATH
    print_success "Nix installed and configured"
    echo ""

    # STEP 5: Clone/update repository
    print_step "4/6" "Setting up Configuration Repository"
    if [ -d "$REPO_DIR" ]; then
        print_info "Repository exists, updating..."
        cd "$REPO_DIR"
        git fetch origin
        git checkout "$REPO_BRANCH"
        git pull origin "$REPO_BRANCH"
    else
        print_info "Cloning repository..."
        mkdir -p "$(dirname "$REPO_DIR")"
        git clone "$REPO_URL" "$REPO_DIR"
        cd "$REPO_DIR"
        git checkout "$REPO_BRANCH"
    fi

    # Create lib and bin directories if they don't exist
    mkdir -p "$REPO_DIR/lib" "$REPO_DIR/bin"

    # Copy wizard files if they exist in the script directory
    if [ -f "$SCRIPT_DIR/lib/ui.sh" ] && [ "$SCRIPT_DIR" != "$REPO_DIR" ]; then
        cp "$SCRIPT_DIR/lib/"*.sh "$REPO_DIR/lib/" 2>/dev/null || true
    fi
    if [ -f "$SCRIPT_DIR/bin/nix-me" ] && [ "$SCRIPT_DIR" != "$REPO_DIR" ]; then
        cp "$SCRIPT_DIR/bin/nix-me" "$REPO_DIR/bin/" 2>/dev/null || true
        chmod +x "$REPO_DIR/bin/nix-me"
    fi

    print_success "Repository ready"
    echo ""

    # STEP 6: Generate machine configuration
    print_step "5/6" "Generating Machine Configuration"
    cd "$REPO_DIR"

    if [ -f "$REPO_DIR/lib/config-builder.sh" ]; then
        source "$REPO_DIR/lib/config-builder.sh"
        generate_machine_config "$HOST_NAME" "$MACHINE_TYPE" "$MACHINE_NAME" "$NIXOS_USERNAME" "$REPO_DIR" "0"
    else
        print_warn "Config builder not available"
        print_info "Please manually add machine to flake.nix"
    fi
    echo ""

    # STEP 7: Build and activate
    print_step "6/6" "Building and Activating System"
    cd "$REPO_DIR"

    # Enable flakes
    mkdir -p ~/.config/nix
    echo "experimental-features = nix-command flakes" > ~/.config/nix/nix.conf

    # Build
    print_info "Building system configuration (this may take 15-30 minutes)..."
    if ! command -v darwin-rebuild &>/dev/null; then
        print_info "Installing nix-darwin..."
        nix build --extra-experimental-features "nix-command flakes" \
            ".#darwinConfigurations.$HOST_NAME.system"
        sudo mkdir -p /etc/nix-darwin /etc/static
        sudo ./result/sw/bin/darwin-rebuild switch --flake ".#$HOST_NAME" --impure
    else
        print_info "Activating configuration..."
        sudo darwin-rebuild switch --flake ".#$HOST_NAME" --impure
    fi

    echo ""
    print_success "Installation complete!"

    echo ""
    print_header "🎉 Welcome to nix-me!"
    echo ""
    echo "  Your macOS system is now managed with Nix."
    echo ""
    echo "  ${GREEN}Next Steps:${NC}"
    echo "  1. Restart your terminal (or run: exec \$SHELL)"
    echo "  2. Run: ${CYAN}nix-me doctor${NC} (check system health)"
    echo "  3. Run: ${CYAN}nix-me customize${NC} (add more apps)"
    echo "  4. Run: ${CYAN}nix-me --help${NC} (see all commands)"
    echo ""
    echo "  ${YELLOW}Useful Commands:${NC}"
    echo "  • ${CYAN}nix-me add app <name>${NC}  - Search and add GUI apps"
    echo "  • ${CYAN}nix-me add tool <name>${NC} - Add CLI tools"
    echo "  • ${CYAN}nix-me setup${NC}           - Re-run setup wizard"
    echo "  • ${CYAN}nix-me switch${NC}          - Apply configuration changes"
    echo ""
    echo "  ${GREEN}Configuration:${NC}"
    echo "  📁 ${REPO_DIR}"
    echo ""
}

main "$@"
