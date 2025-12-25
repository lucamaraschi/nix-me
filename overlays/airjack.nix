# AirJack - macOS WiFi Security Testing Tool
# https://github.com/rtulke/AirJack
#
# Since AirJack requires pyobjc-framework-CoreWLAN which isn't in nixpkgs,
# we provide a setup script that installs it via pip in a virtual environment.
final: prev:

{
  airjack = prev.writeShellApplication {
    name = "airjack";
    runtimeInputs = with prev; [
      python3
      git
    ];
    text = ''
      AIRJACK_HOME="$HOME/.local/share/airjack"
      VENV_PATH="$AIRJACK_HOME/venv"
      REPO_PATH="$AIRJACK_HOME/repo"

      # First-time setup
      if [ ! -d "$VENV_PATH" ] || [ ! -d "$REPO_PATH" ]; then
        echo "Setting up AirJack for the first time..."
        mkdir -p "$AIRJACK_HOME"

        # Clone repository if not present
        if [ ! -d "$REPO_PATH" ]; then
          echo "Cloning AirJack repository..."
          git clone https://github.com/rtulke/AirJack.git "$REPO_PATH"
        fi

        # Create virtual environment if not present
        if [ ! -d "$VENV_PATH" ]; then
          echo "Creating Python virtual environment..."
          python3 -m venv "$VENV_PATH"
          # shellcheck source=/dev/null
          source "$VENV_PATH/bin/activate"
          echo "Installing dependencies..."
          pip install --upgrade pip
          pip install prettytable pyfiglet scapy
          pip install pyobjc-framework-CoreWLAN pyobjc-framework-CoreLocation
          deactivate
        fi

        echo "AirJack setup complete!"
        echo ""
      fi

      # Run AirJack
      # shellcheck source=/dev/null
      source "$VENV_PATH/bin/activate"
      cd "$REPO_PATH"
      python3 airjack.py "$@"
    '';
  };

  # Helper to update AirJack
  airjack-update = prev.writeShellApplication {
    name = "airjack-update";
    runtimeInputs = with prev; [
      git
    ];
    text = ''
      AIRJACK_HOME="$HOME/.local/share/airjack"
      REPO_PATH="$AIRJACK_HOME/repo"
      VENV_PATH="$AIRJACK_HOME/venv"

      if [ ! -d "$REPO_PATH" ]; then
        echo "AirJack not installed. Run 'airjack' first to set up."
        exit 1
      fi

      echo "Updating AirJack..."
      cd "$REPO_PATH"
      git pull origin main

      echo "Updating Python dependencies..."
      # shellcheck source=/dev/null
      source "$VENV_PATH/bin/activate"
      pip install --upgrade prettytable pyfiglet scapy
      pip install --upgrade pyobjc-framework-CoreWLAN pyobjc-framework-CoreLocation
      deactivate

      echo "AirJack updated successfully!"
    '';
  };
}
