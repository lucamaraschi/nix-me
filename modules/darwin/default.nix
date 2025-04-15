{ pkgs, ... }:

{
  imports = [
    ./core.nix
    ./fonts.nix
    ./system.nix
    ./apps.nix
    ./homebrew.nix
    ./keyboard.nix
    ./shell.nix
  ];
}