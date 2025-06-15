# modules/darwin/core.nix
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
    
    # Enable nix (was previously disabled)
    enable = lib.mkDefault true;
    
    # Optimization settings with defaults
    optimise.automatic = lib.mkDefault false;

    # Garbage collection with defaults
    gc = {
      automatic = lib.mkDefault false;
      interval = lib.mkDefault { 
        Hour = 3;
        Minute = 0;
      };
      options = lib.mkDefault "--delete-older-than 30d";
    };
    
    # Nix settings
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      warn-dirty = false;
    };
    
    # Updated nixPath configuration
    nixPath = [
      "darwin-config=/etc/nix-darwin/configuration.nix"
      "darwin=$HOME/.nix-defexpr/channels/darwin"
      "nixpkgs=$HOME/.nix-defexpr/channels/nixpkgs"
      "$HOME/.nix-defexpr/channels"
    ];
  };
  
  # Environment setup
  environment = {
    # System-level packages - consolidated here to avoid conflicts
    systemPackages = lib.mkDefault (with pkgs; [
      # Core system tools
      coreutils
      curl
      wget
      git
      vim
      
      # Development tools (from apps.nix)
      jq
      ripgrep
      fd
      eza
      bat
      tree
      htop
      ncdu
      nodejs
      python3
      rustup
      go
      git-lfs
      gh
      nmap
      dnsutils
      mtr
      nixpkgs-fmt
      comma
      pandoc
      imagemagick
      
      # Display tools (from display.nix)
      gnugrep
      gnused
    ]);
    
    # Set system-wide shell variables
    variables = lib.mkDefault {
      EDITOR = "vim";
      VISUAL = "vim";
    };
    
    # System PATH - use mkDefault so it can be overridden
    systemPath = lib.mkDefault [ "/opt/homebrew/bin" ];
    pathsToLink = lib.mkDefault [ "/Applications" ];
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