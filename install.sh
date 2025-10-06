#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source UI library
if [ -f "$SCRIPT_DIR/lib/ui.sh" ]; then
    source "$SCRIPT_DIR/lib/ui.sh"
else
    print_header() { echo "=== $1 ==="; }
    print_success() { echo "✓ $1"; }
    print_error() { echo "✗ $1"; }
    print_info() { echo "• $1"; }
    print_warn() { echo "⚠ $1"; }
    print_step() { echo "[$1] $2"; }
    ask_yes_no() { read -p "$1 (Y/n): " answer; [[ -z $answer || $answer =~ ^[Yy] ]]; }
fi

main() {
    # Control variables
    FORCE_NIX_REINSTALL=${FORCE_NIX_REINSTALL:-0}
    NON_INTERACTIVE=${NON_INTERACTIVE:-0}
    USE_WIZARD=${USE_WIZARD:-1}

    REPO_URL=${REPO_URL:-"https://github.com/lucamaraschi/nix-me.git"}
    REPO_BRANCH=${REPO_BRANCH:-"main"}
    REPO_DIR=${HOME}/.config/nixpkgs

    # Run wizard if appropriate
    if [ $# -eq 0 ] && [ "$NON_INTERACTIVE" != "1" ] && [ "$USE_WIZARD" == "1" ]; then
        if [ -f "$SCRIPT_DIR/lib/wizard.sh" ]; then
            source "$SCRIPT_DIR/lib/wizard.sh"

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
            print_warn "Wizard not available, using defaults"
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
    print_header "nix-me Installation"
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

    # Verify macOS
    if [[ "$OSTYPE" != "darwin"* ]]; then
        print_error "This script must be run on macOS"
        exit 1
    fi

    # Request sudo
    print_info "Requesting administrator privileges..."
    sudo -v || { print_error "Authentication failed"; exit 1; }

    # Sudo refresh background process
    ( while true; do sudo -v; sleep 60; done ) &
    SUDO_REFRESH_PID=$!
    trap "kill $SUDO_REFRESH_PID 2>/dev/null || true" EXIT

    # Install Xcode CLI tools
    print_step "1/5" "Checking Xcode Command Line Tools"
    if [[ -z "$(command -v git)" ]]; then
        print_info "Installing Xcode Command Line Tools..."
        xcode-select --install &> /dev/null
        print_info "Waiting for installation to complete..."
        until xcode-select --print-path &> /dev/null; do sleep 5; done
    fi
    print_success "Xcode Command Line Tools ready"
    echo ""

    # Install Nix
    print_step "2/5" "Installing Nix"
    if ! command -v nix &>/dev/null || [ "$FORCE_NIX_REINSTALL" == "1" ]; then
        print_info "Installing Nix package manager..."
        curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install

        # Source Nix environment
        if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
            source '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
        fi
    fi
    export PATH=$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$PATH
    print_success "Nix installed"
    echo ""

    # Clone/update repository
    print_step "3/5" "Setting up configuration repository"
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

    # Create lib and bin directories
    mkdir -p "$REPO_DIR/lib" "$REPO_DIR/bin"

    # Copy wizard files if they exist
    if [ -f "$SCRIPT_DIR/lib/ui.sh" ]; then
        cp "$SCRIPT_DIR/lib/"*.sh "$REPO_DIR/lib/" 2>/dev/null || true
    fi
    if [ -f "$SCRIPT_DIR/bin/nix-me" ]; then
        cp "$SCRIPT_DIR/bin/nix-me" "$REPO_DIR/bin/" 2>/dev/null || true
        chmod +x "$REPO_DIR/bin/nix-me"
    fi

    print_success "Repository ready"
    echo ""

    # Generate machine configuration
    print_step "4/5" "Generating machine configuration"
    if [ -f "$REPO_DIR/lib/config-builder.sh" ]; then
        source "$REPO_DIR/lib/config-builder.sh"
        generate_machine_config "$HOST_NAME" "$MACHINE_TYPE" "$MACHINE_NAME" "$NIXOS_USERNAME" "$REPO_DIR" "0"
    else
        print_warn "Config builder not available"
        print_info "Please manually add machine to flake.nix"
    fi
    echo ""

    # Build and activate
    print_step "5/5" "Building and activating system"
    cd "$REPO_DIR"

    # Enable flakes
    mkdir -p ~/.config/nix
    echo "experimental-features = nix-command flakes" > ~/.config/nix/nix.conf

    # Build
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

    print_success "Installation complete!"

    echo ""
    print_header "Next Steps"
    echo ""
    echo "  1. Restart your terminal"
    echo "  2. Run: nix-me doctor"
    echo "  3. Customize: nix-me customize"
    echo "  4. Add apps: nix-me add app spotify"
    echo ""
}

main "$@"
#!/bin/bash

set -e

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source UI library if available
if [ -f "$SCRIPT_DIR/lib/ui.sh" ]; then
    source "$SCRIPT_DIR/lib/ui.sh"
else
    # Fallback to simple output
    print_header() { echo "=== $1 ==="; }
    print_success() { echo "✓ $1"; }
    print_error() { echo "✗ $1"; }
    print_info() { echo "• $1"; }
    print_warn() { echo "⚠ $1"; }
    print_step() { echo "[$1] $2"; }
fi

# Check if running with wizard mode
USE_WIZARD=${USE_WIZARD:-1}

main() {
    # Allow environment variables to control behavior
    FORCE_NIX_REINSTALL=${FORCE_NIX_REINSTALL:-0}
    NON_INTERACTIVE=${NON_INTERACTIVE:-0}
    SKIP_BREW_ON_VM=${SKIP_BREW_ON_VM:-0}

    # Run wizard if no arguments provided and not non-interactive
    if [ $# -eq 0 ] && [ "$NON_INTERACTIVE" != "1" ] && [ "$USE_WIZARD" == "1" ]; then
        if [ -f "$SCRIPT_DIR/lib/wizard.sh" ]; then
            source "$SCRIPT_DIR/lib/wizard.sh"

            if run_setup_wizard; then
                # Use wizard values
                HOST_NAME=${WIZARD_HOSTNAME}
                MACHINE_TYPE=${WIZARD_MACHINE_TYPE}
                MACHINE_NAME=${WIZARD_MACHINE_NAME}
                NIXOS_USERNAME=${WIZARD_USERNAME}
                CONFIG_PROFILE=${WIZARD_CONFIG_PROFILE:-standard}
            else
                print_error "Wizard cancelled or failed"
                exit 1
            fi
        else
            print_warn "Wizard not available, using command-line mode"
            USE_WIZARD=0
        fi
    fi

    # Fall back to command-line arguments if wizard wasn't used
    if [ "$USE_WIZARD" != "1" ]; then
        HOST_NAME=${1:-$(hostname -s)}
        MACHINE_TYPE=${2:-""}
        MACHINE_NAME=${3:-"$HOST_NAME"}
        NIXOS_USERNAME=${4:-$(whoami)}
        CONFIG_PROFILE=${5:-standard}
    fi

    REPO_URL=${REPO_URL:-"https://github.com/lucamaraschi/nix-me.git"}
    REPO_BRANCH=${REPO_BRANCH:-"main"}
    REPO_DIR=${HOME}/.config/nixpkgs

    # Auto-detect machine type if not provided
    if [[ -z "$MACHINE_TYPE" ]]; then
        if [[ "$HOST_NAME" == *"macbook"* || "$HOST_NAME" == *"mba"* ]]; then
            MACHINE_TYPE="macbook"
        elif [[ "$HOST_NAME" == *"mini"* ]]; then
            MACHINE_TYPE="macmini"
        else
            MACHINE_TYPE="macbook"  # default
        fi
        print_info "Auto-detected machine type: $MACHINE_TYPE"
    fi

    # Set HOST environment variable
    export HOST="$HOST_NAME"

    # Print configuration summary
    print_header "nix-me Installation"
    echo ""
    echo "  Hostname:       $HOST_NAME"
    echo "  Machine Type:   $MACHINE_TYPE"
    echo "  Machine Name:   $MACHINE_NAME"
    echo "  Username:       $NIXOS_USERNAME"
    echo "  Profile:        $CONFIG_PROFILE"
    echo "  Repository:     $REPO_URL"
    echo "  Branch:         $REPO_BRANCH"
    echo ""

    # Verify we're on macOS
    if [[ "$OSTYPE" != "darwin"* ]]; then
        print_error "This script must be run on macOS"
        exit 1
    fi

    # Request sudo privileges
    print_info "Requesting administrator privileges..."
    sudo -v || { print_error "Authentication failed"; exit 1; }

    # Start background sudo refresh
    ( while true; do sudo -v; sleep 60; done ) &
    SUDO_REFRESH_PID=$!

    # Cleanup function
    cleanup() {
        if [[ -n "$SUDO_REFRESH_PID" ]]; then
            kill "$SUDO_REFRESH_PID" >/dev/null 2>&1 || true
        fi
    }
    trap cleanup EXIT

    # Install Xcode Command Line Tools if needed
    if [[ -z "$(command -v git)" ]]; then
        print_info "Installing Xcode Command Line Tools"
        xcode-select --install &> /dev/null

        print_info "Waiting for Xcode Command Line Tools installation..."
        until xcode-select --print-path &> /dev/null; do
            sleep 5
        done
    else
        print_success "Xcode Command Line Tools already installed"
    fi

    # Install Nix (placeholder - use your existing install_or_fix_nix function)
    print_step "1/4" "Installing Nix"
    if ! command -v nix &>/dev/null; then
        curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
    fi
    print_success "Nix installed"

    # Clone or update repository
    print_step "2/4" "Setting up configuration repository"
    if [ -d "$REPO_DIR" ]; then
        print_info "Repository exists, updating..."
        cd "$REPO_DIR"
        git pull
    else
        print_info "Cloning configuration repository..."
        mkdir -p "$(dirname "$REPO_DIR")"
        git clone "$REPO_URL" "$REPO_DIR"
        cd "$REPO_DIR"
        git checkout "$REPO_BRANCH"
    fi
    print_success "Repository ready"

    # Generate machine configuration
    print_step "3/4" "Generating machine configuration"
    if [ -f "$SCRIPT_DIR/lib/config-builder.sh" ]; then
        source "$SCRIPT_DIR/lib/config-builder.sh"
        generate_machine_config "$HOST_NAME" "$MACHINE_TYPE" "$MACHINE_NAME" "$NIXOS_USERNAME" "$CONFIG_PROFILE"
    else
        print_warn "Config builder not available, manual configuration required"
    fi

    # Build and activate configuration
    print_step "4/4" "Building and activating system"
    cd "$REPO_DIR"

    # Ensure flakes are enabled
    mkdir -p ~/.config/nix
    echo "experimental-features = nix-command flakes" > ~/.config/nix/nix.conf

    # Install nix-darwin if not already installed
    if ! command -v darwin-rebuild &> /dev/null; then
        print_info "Installing nix-darwin..."
        nix build --extra-experimental-features "nix-command flakes" \
            ".#darwinConfigurations.$HOST_NAME.system"
        sudo mkdir -p /etc/nix-darwin /etc/static
        sudo ./result/sw/bin/darwin-rebuild switch --flake ".#$HOST_NAME"
    else
        print_info "Activating configuration..."
        sudo darwin-rebuild switch --flake ".#$HOST_NAME" --impure
    fi

    print_success "Installation completed!"

    echo ""
    print_header "Next Steps"
    echo ""
    echo "  1. Restart your terminal"
    echo "  2. Customize: nix-me customize"
    echo "  3. Add apps: nix-me add app <name>"
    echo "  4. Check status: nix-me doctor"
    echo ""
}

# Run main function
main "$@"
