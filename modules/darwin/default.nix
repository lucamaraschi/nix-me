{ lib, ... }:

{
  imports = [
    ./apps  # Uses apps/default.nix which imports all app modules
    ./core.nix
    ./display.nix
    ./fonts.nix
    ./keyboard.nix
    ./project-sync.nix
    ./shell.nix
    ./system.nix
  ];
}
