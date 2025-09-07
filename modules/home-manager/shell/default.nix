
# modules/home-manager/shell/default.nix
{ lib, ... }:

{
  imports = [
    ./fish.nix
    ./direnv.nix
    # Add more shell-related configurations here:
    # ./starship.nix
    # ./zsh.nix
    # ./bash.nix
  ];
}