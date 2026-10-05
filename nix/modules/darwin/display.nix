# modules/darwin/display.nix
# Display configuration module - sets displays to maximum resolution ("More Space")
#
# This module is DISABLED by default. To enable it, set:
#   display.autoConfigureResolution = true;
#
# Requires displayplacer which is installed via Homebrew when enabled.
{ config, lib, pkgs, machineType ? null, ... }:

{
  options.display = {
    autoConfigureResolution = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Automatically configure displays to maximum resolution (More Space)";
    };
  };

  config = lib.mkIf (config.display.autoConfigureResolution && machineType != "vm") {
    # Install displayplacer via Homebrew (runs before activation scripts)
    homebrew.brews = [ "jakehilborn/jakehilborn/displayplacer" ];

    # Add resolution setting script to activation
    system.activationScripts.extraActivation.text = lib.mkAfter ''
      echo "Setting display resolution to maximum (More Space)..." >&2

      # Create a script to handle display configuration
      mkdir -p "$HOME"/.config/nixpkgs/scripts
      cat > "$HOME"/.config/nixpkgs/scripts/configure-displays.sh << 'EOF'
#!/bin/bash

# Script to configure all displays to their maximum resolution
# Handles multiple displays with different IDs correctly

set -e

# Function to log messages
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$HOME/.config/nixpkgs/display-config.log"
}

log "Starting display configuration"

# Check if displayplacer is available
if ! command -v displayplacer >/dev/null 2>&1; then
  log "Warning: displayplacer not found - skipping display configuration"
  log "You can enable it by setting: display.autoConfigureResolution = true;"
  exit 0
fi

# Get current display configuration
log "Getting current display configuration"
if ! CURRENT_CONFIG=$(displayplacer list 2>/dev/null); then
  log "Warning: Could not get display configuration"
  exit 0
fi

# Parse all displays and their IDs
DISPLAYS=$(echo "$CURRENT_CONFIG" | grep -E "Display [0-9]+" | sed -E 's/.*Display ([0-9]+).*/\1/')

if [ -z "$DISPLAYS" ]; then
  log "No displays found, skipping configuration"
  exit 0
fi

log "Found displays: $DISPLAYS"

# Process each display
for DISPLAY_ID in $DISPLAYS; do
  log "Processing display $DISPLAY_ID"

  # Extract all available resolutions for this display
  RESOLUTIONS=$(echo "$CURRENT_CONFIG" | grep -A 50 "Display $DISPLAY_ID" | grep -E "Resolution.*Hz" | sed -E 's/.*Resolution (.*) @.*/\1/' | sort -t x -k1,1nr -k2,2nr)

  if [ -z "$RESOLUTIONS" ]; then
    log "No resolutions found for display $DISPLAY_ID, skipping"
    continue
  fi

  # Get the highest resolution
  HIGHEST_RES=$(echo "$RESOLUTIONS" | head -1)
  log "Highest resolution for display $DISPLAY_ID: $HIGHEST_RES"

  # Get the current origin for this display (to maintain position)
  ORIGIN=$(echo "$CURRENT_CONFIG" | grep -A 2 "Display $DISPLAY_ID" | grep "Origin" | sed -E 's/.*Origin (.*) -.*/\1/')

  if [ -z "$ORIGIN" ]; then
    log "No origin found for display $DISPLAY_ID, using 0,0"
    ORIGIN="0,0"
  fi

  # Build the command for this display
  DISPLAY_CMD="id:$DISPLAY_ID mode:$HIGHEST_RES origin:$ORIGIN degree:0 hz:60 scaling:on"
  log "Display command: $DISPLAY_CMD"

  # Store this display's command for later
  DISPLAY_CMDS="$DISPLAY_CMDS $DISPLAY_CMD"
done

# Execute the final command with all displays
if [ -n "$DISPLAY_CMDS" ]; then
  FINAL_CMD="displayplacer$DISPLAY_CMDS"
  log "Executing final command: $FINAL_CMD"
  if eval "$FINAL_CMD" 2>/dev/null; then
    log "Display configuration applied successfully"
  else
    log "Warning: Display configuration command failed, but continuing anyway"
  fi
else
  log "No display configurations to apply"
fi
EOF

      # Make the script executable
      chmod +x "$HOME"/.config/nixpkgs/scripts/configure-displays.sh

      # Run the display configuration script (with error handling)
      if "$HOME"/.config/nixpkgs/scripts/configure-displays.sh 2>/dev/null; then
        echo "Display configuration completed" >&2
      else
        echo "Warning: Display configuration failed, but system activation continues" >&2
      fi
    '';
  };
}
