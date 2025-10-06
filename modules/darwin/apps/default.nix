{ lib, ... }:

{
  imports = [
    ./installations.nix
    ./nix-me.nix
    ./raycast.nix
    ./rectangle.nix
    ./vm-manager.nix
    # Add more system-level app configurations here:
    # ./hammerspoon.nix
    # ./hiddenbar.nix
    # ./docker.nix
  ];
}
