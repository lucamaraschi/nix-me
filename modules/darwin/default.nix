{ lib, ... }:

{
  imports = [
    ./core.nix
    ./display.nix
    ./fonts.nix
    ./homebrew.nix
    ./keyboard.nix
    ./shell.nix
    ./system.nix
  ];
}