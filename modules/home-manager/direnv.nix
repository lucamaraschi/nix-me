# modules/home-manager/direnv.nix
{ config, lib, pkgs, ... }:

{
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    
    stdlib = ''
      # Reload direnv when these files change
      watch_file flake.nix
      watch_file flake.lock
      watch_file shell.nix
      watch_file .envrc
      
      # Node.js environment with local packages
      layout_node() {
        export NODE_PATH="$PWD/node_modules"
        PATH_add node_modules/.bin
      }
    '';
    
    # enableFishIntegration = true;
  };
  
  # Add .envrc templates to help with common project types
  home.file.".config/direnv/templates/node.envrc".text = ''
    # Node.js project
    layout node
    
    # Load environment variables from .env file if it exists
    if [ -f .env ]; then
      source_env .env
    fi
  '';
  
  home.file.".config/direnv/templates/nix.envrc".text = ''
    # Nix project with flake
    if [ -f flake.nix ]; then
      use flake
    # Fallback to shell.nix if there's no flake
    elif [ -f shell.nix ]; then
      use nix
    fi
    
    # Load environment variables from .env file if it exists
    if [ -f .env ]; then
      source_env .env
    fi
  '';
}