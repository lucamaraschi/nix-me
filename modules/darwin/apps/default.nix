{ lib, ... }:

{
  imports = [
    ./installations.nix
    ./nix-me.nix
    ./rectangle.nix
    ./vm-manager.nix
    # Add more system-level app configurations here:
    # ./hammerspoon.nix
    # ./hiddenbar.nix
    # ./raycast.nix (empty file - add config when needed)
    # ./docker.nix
  ];
}
