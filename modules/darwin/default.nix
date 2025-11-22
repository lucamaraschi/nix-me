{ lib, ... }:

{
  imports = [
    ./apps/installations.nix
    ./core.nix
    ./display.nix
    ./fonts.nix
    ./keyboard.nix
    ./shell.nix
    ./system.nix
  ];
}