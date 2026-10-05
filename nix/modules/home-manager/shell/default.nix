
# modules/home-manager/shell/default.nix
{ lib, ... }:

{
  imports = [
    ./fish.nix
    ./direnv.nix
    ./starship.nix
    # ./zsh.nix
    # ./bash.nix
  ];
}