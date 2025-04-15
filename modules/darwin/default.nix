{ lib, ... }:

{
  imports = [
    ./apps.nix
    ./core.nix
    ./display.nix
    ./fonts.nix
    ./homebrew.nix
    ./keyboard.nix
    ./shell.nix
    ./system.nix
  ];
}