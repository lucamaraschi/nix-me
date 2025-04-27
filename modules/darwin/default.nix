{ pkgs, ... }:

{
  imports = [
    ./apps.nix
    ./core.nix
    ./darwin.nix
    ./display.nix
    ./fonts.nix
    ./homebrew.nix
    ./keyboard.nix
    ./shell.nix
    ./system.nix
  ];
}