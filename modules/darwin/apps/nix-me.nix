{ config, pkgs, lib, username, ... }:

let
  # Create nix-me CLI wrapper
  nix-me-cli = pkgs.writeScriptBin "nix-me" ''
    #!${pkgs.bash}/bin/bash
    SCRIPT_DIR="${config.users.users.${username}.home}/.config/nixpkgs"

    if [ ! -f "$SCRIPT_DIR/bin/nix-me" ]; then
      echo "Error: nix-me not found at $SCRIPT_DIR/bin/nix-me"
      echo "Please ensure your nix-me configuration is properly installed"
      exit 1
    fi

    exec "$SCRIPT_DIR/bin/nix-me" "$@"
  '';
in
{
  # Add nix-me to system packages
  environment.systemPackages = [ nix-me-cli ];
}
