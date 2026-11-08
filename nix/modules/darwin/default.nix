{ lib, ... }:

{
  imports = [
    ./activation-runner.nix
    ./apps # Uses apps/default.nix which imports all app modules
    ./core.nix
    ./display.nix
    ./fonts.nix
    ./keyboard.nix
    ./management-api.nix
    ./machine-state.nix
    ./project-sync.nix
    ./shell.nix
    ./system.nix
  ];
}
