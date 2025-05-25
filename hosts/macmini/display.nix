# hosts/macmini/display.nix
{ config, lib, pkgs, ... }:

{
  # Mac Mini specific display settings
  system.activationScripts.macminiDisplay.text = lib.mkAfter ''
    # For Mac Mini, we might have a specific multi-monitor setup
    if [[ "$(hostname -s)" == "mac-mini" ]]; then
      # Example: If this is a known setup with specific arrangement
      if [ -f "$HOME/.config/nixpkgs/scripts/configure-displays.sh" ]; then
        "$HOME"/.config/nixpkgs/scripts/configure-displays.sh
      fi
    fi
  '';
}