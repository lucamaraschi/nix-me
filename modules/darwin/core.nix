{ pkgs, config, lib, username, ... }:

{
  system.stateVersion = 6;
  nixpkgs.config.allowUnfree = true;

  # Explicitly configure the primary user
  users.users.${username} = {
    name = username;
    home = "/Users/${username}";
  };

  # Core system configuration
  nix = {
    package = pkgs.nix;
    optimise.automatic = false;

    # Garbage collection
    gc = {
      automatic = false;
      interval = { 
        Hour = 3;
        Minute = 0;
      };
      options = "--delete-older-than 30d";
    };
    
    # Nix settings
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      warn-dirty = false;
    };
    
    # Updated nixPath configuration (no longer uses primaryUserHome)
    nixPath = [
      "darwin-config=/etc/nix-darwin/configuration.nix"
      "darwin=$HOME/.nix-defexpr/channels/darwin"
      "nixpkgs=$HOME/.nix-defexpr/channels/nixpkgs"
      "$HOME/.nix-defexpr/channels"
    ];
  };

  # Enable nix-darwin services
  nix.enable = false;
  
  # Environment setup
  environment = {
    # System-level packages
    systemPackages = with pkgs; [
      coreutils
      curl
      wget
      git
      vim
    ];
    
    # Set system-wide shell variables
    variables = {
      EDITOR = "vim";
      VISUAL = "vim";
    };
    
    # Disable manual
    systemPath = [ "/opt/homebrew/bin" ];
    pathsToLink = [ "/Applications" ];
  };
  
  # System activation
  system.activationScripts.postActivation.text = ''
    # Reset LaunchPad
    echo "Resetting LaunchPad..." >&2
    find ~/Library/Application\ Support/Dock -name "*.db" -maxdepth 1 -delete

    # Touch a last-rebuild file so we can tell when the system was last rebuilt
    printf "%s" "$(date)" > "$HOME"/.nix-last-rebuild
  '';
}