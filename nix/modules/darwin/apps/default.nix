{ lib, ... }:

{
  imports = [
    ./installations.nix
    ./codex.nix
    ./nix-me.nix
    ./vm-manager.nix
    ./1password.nix
    ./raycast.nix
    # Add more system-level app configurations here:
    # ./hammerspoon.nix
    # ./docker.nix
    # Note: rectangle.nix moved to modules/home-manager/rectangle.nix (uses home.file)
  ];
}
