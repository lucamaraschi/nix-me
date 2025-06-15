# modules/darwin/homebrew.nix
{ config, lib, pkgs, ... }:

let
  # Define base lists (these don't reference config, so no recursion)
  baseLists = {
    casks = [
      # Communication & Collaboration
      "linear-linear"
      "loom"
      "microsoft-teams"
      "miro"
      "slack"
      "zoom"
      
      # Productivity
      "1password"
      "hiddenbar"
      "raycast"
      "rectangle"
      
      # Development
      "docker"
      "ghostty"
      "github"
      "orbstack"
      "orka-desktop"
      "visual-studio-code"
      
      # Browsers
      "google-chrome"
      
      # Graphics & Design
      "adobe-creative-cloud"
      "figma"
      
      # Microsoft Office
      "microsoft-office"
      
      # Utilities
      "hammerspoon"
      "proton-mail"
      "protonvpn"
      "utm"
      "virtualbuddy"
      "vmware-fusion"
      
      # Media
      "obs"
      "spotify"
    ];

    brews = [
      "coreutils"
      "direnv"
      "fd" 
      "gcc"
      "git"
      "grep"
      "helm"
      "jq"
      "k3d"
      "mas"
      "pnpm"
      "ripgrep"
      "terraform"
      "trash"
    ];

    masApps = {
      Tailscale = 1475387142;
      Xcode = 497799835;
      "iA-Writer" = 775737590;
    };
  };

in
{
  # Export the base lists so other modules can reference them
  options.homebrew = {
    # Expose base lists for reference
    baseCasks = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = baseLists.casks;
      readOnly = true;
      description = "Base list of casks that can be referenced by machine configs";
    };
    
    baseBrews = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = baseLists.brews;
      readOnly = true;
      description = "Base list of brews that can be referenced by machine configs";
    };
    
    baseMasApps = lib.mkOption {
      type = lib.types.attrsOf lib.types.int;
      default = baseLists.masApps;
      readOnly = true;
      description = "Base list of MAS apps that can be referenced by machine configs";
    };
    
    # Option to use base lists with modifications
    useBaseLists = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to use base lists with add/remove modifications";
    };

    casksToRemove = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "List of casks to remove from the base list";
    };
    
    casksToAdd = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "List of additional casks to install";
    };
    
    brewsToRemove = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "List of brews to remove from the base list";
    };
    
    brewsToAdd = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "List of additional brews to install";
    };
    
    # MAS Apps options
    masAppsToRemove = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "List of MAS app names to remove from the base list";
    };
    
    masAppsToAdd = lib.mkOption {
      type = lib.types.attrsOf lib.types.int;
      default = {};
      description = "Additional MAS apps to install (name = appStoreId)";
    };
  };

  config = {
    homebrew = {
      enable = lib.mkDefault true;
      onActivation = {
        autoUpdate = lib.mkDefault true;
        cleanup = lib.mkDefault "zap";
      };
      
      taps = lib.mkDefault [];

      # Global Homebrew settings to reduce sudo requirements
      global = {
        # Use /opt/homebrew on Apple Silicon, /usr/local on Intel
        brewfile = true;
        noLock = true; # Reduce file locking that might need sudo
      };
      
      # Move calculations here to avoid recursion
      casks = lib.mkDefault (
        if config.homebrew.useBaseLists
        then (lib.subtractLists config.homebrew.casksToRemove baseLists.casks) ++ config.homebrew.casksToAdd
        else baseLists.casks  # Use base list as default
      );
      
      brews = lib.mkDefault (
        if config.homebrew.useBaseLists
        then (lib.subtractLists config.homebrew.brewsToRemove baseLists.brews) ++ config.homebrew.brewsToAdd
        else baseLists.brews  # Use base list as default
      );
      
      masApps = lib.mkDefault (
        let
          finalMasApps = if config.homebrew.useBaseLists
            then (baseLists.masApps // config.homebrew.masAppsToAdd) // (lib.genAttrs config.homebrew.masAppsToRemove (_: null))
            else baseLists.masApps;
        in
          lib.filterAttrs (name: id: id != null) finalMasApps
      );
    };
  };
}