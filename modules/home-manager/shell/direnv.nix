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

      layout_nodejs() {
        local version=${1:-22}
        export NODE_VERSION=$version
        PATH_add node_modules/.bin
        export NPM_CONFIG_PREFIX=$PWD/.npm-global
        PATH_add .npm-global/bin
      }
  
      # Automatic package manager detection
      layout_node_auto() {
        if [[ -f pnpm-lock.yaml ]]; then
          echo "Using pnpm"
          layout_nodejs && pnpm install
        elif [[ -f yarn.lock ]]; then
          echo "Using yarn"  
          layout_nodejs && yarn install
        else
          echo "Using npm"
          layout_nodejs && npm install
        fi
      }

      # Simple Node.js layout without needing shell.nix
      layout_node_global() {
        echo "Using global Node.js $(node --version)"
        PATH_add node_modules/.bin
        export NPM_CONFIG_PREFIX=$PWD/.npm-global
        PATH_add .npm-global/bin
        
        # Auto-install dependencies if package.json exists
        if [[ -f package.json ]] && [[ ! -d node_modules ]]; then
          if [[ -f pnpm-lock.yaml ]]; then
            echo "Installing dependencies with pnpm..."
            pnpm install
          else
            echo "Installing dependencies with npm..."
            npm install
          fi
        fi
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