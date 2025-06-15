# modules/darwin/homebrew.nix
{ config, lib, pkgs, ... }:

let
  cfg = config.homebrew;
  
  # Define base lists that can be referenced by other modules
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

  # Calculate final lists based on base + modifications
  finalCasks = if cfg.useBaseLists
    then (lib.subtractLists cfg.casksToRemove baseLists.casks) ++ cfg.casksToAdd
    else cfg.casks;
    
  finalBrews = if cfg.useBaseLists
    then (lib.subtractLists cfg.brewsToRemove baseLists.brews) ++ cfg.brewsToAdd  
    else cfg.brews;
    
  finalMasApps = if cfg.useBaseLists
    then (baseLists.masApps // cfg.masAppsToAdd) // (lib.genAttrs cfg.masAppsToRemove (_: null))
    else cfg.masApps;

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
      
      # Use either the calculated lists or fall back to defaults
      casks = lib.mkDefault finalCasks;
      brews = lib.mkDefault finalBrews;
      masApps = lib.mkDefault (lib.filterAttrs (name: id: id != null) finalMasApps);
    };
  };
}