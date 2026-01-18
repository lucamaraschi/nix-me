{ lib, ... }:

{
  imports = [
    ./installations.nix
    ./nix-me.nix
    ./vm-manager.nix
    ./1password.nix
    ./raycast.nix
    ./hiddenbar.nix
    # Add more system-level app configurations here:
    # ./hammerspoon.nix
    # ./docker.nix
    # Note: rectangle.nix moved to modules/home-manager/rectangle.nix (uses home.file)
  ];
}
