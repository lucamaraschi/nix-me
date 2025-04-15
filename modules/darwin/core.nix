{ pkgs, ... }:

{
  # Core system configuration
  nix = {
    package = pkgs.nix;
    
    # Garbage collection
    gc = {
      automatic = true;
      interval = { 
        Hour = 3;
        Minute = 0;
      };
      options = "--delete-older-than 30d";
    };
    
    # Nix settings
    settings = {
      auto-optimise-store = true;
      experimental-features = [ "nix-command" "flakes" ];
      warn-dirty = false;
    };
    
    # Nix path
    nixPath = [
      "darwin-config=$HOME/.config/nixpkgs/darwin-configuration.nix"
      "darwin=$HOME/.nix-defexpr/channels/darwin"
      "nixpkgs=$HOME/.nix-defexpr/channels/nixpkgs"
      "$HOME/.nix-defexpr/channels"
    ];
  };

  # Enable nix-darwin services
  services.nix-daemon.enable = true;
  
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
    printf "%s" "$(date)" > $HOME/.nix-last-rebuild
  '';
}