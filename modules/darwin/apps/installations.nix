# Centralized app installation management (moved from homebrew.nix)
{ config, lib, pkgs, ... }:

let
  # Define base lists (these don't reference config, so no recursion)
  baseLists = {
    # System packages via Nix
    systemPackages = [
      # Development tools
      "jq"
      "ripgrep"
      "fd"
      "eza"
      "bat"
      "tree"
      "htop"
      "ncdu"
      "nodejs"
      "python3"
      "rustup"
      "go"
      "gh"
      "nmap"
      "dnsutils"
      "mtr"
      "nixpkgs-fmt"
      "comma"
      "pandoc"
      "imagemagick"
    ];

    # GUI applications via Homebrew casks
    casks = [
      # Communication & Collaboration
      "linear-linear"
      "loom"
      "microsoft-teams"
      "miro"
      "slack"
      "zoom"
      
      # Productivity & Utilities
      "1password"
      "hiddenbar"
      "raycast"
      "rectangle"
      "hammerspoon"
      "proton-mail"
      "protonvpn"
      
      # Development
      "docker-desktop"
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
      
      # Virtualization
      "utm"
      "virtualbuddy"
      "vmware-fusion"
      
      # Media
      "obs"
      "spotify"
    ];

    # CLI tools via Homebrew
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

    # Mac App Store applications
    masApps = {
      Tailscale = 1475387142;
      Xcode = 497799835;
      "iA-Writer" = 775737590;
    };
  };

in
{
  # Export the base lists so other modules can reference them
  options.apps = {
    # System packages options
    baseSystemPackages = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = baseLists.systemPackages;
      readOnly = true;
      description = "Base list of system packages";
    };
    
    systemPackagesToRemove = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "System packages to remove from base list";
    };
    
    systemPackagesToAdd = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Additional system packages to install";
    };
    
    # Homebrew options (moved from homebrew.nix)
    baseCasks = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = baseLists.casks;
      readOnly = true;
      description = "Base list of casks";
    };
    
    baseBrews = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = baseLists.brews;
      readOnly = true;
      description = "Base list of brews";
    };
    
    baseMasApps = lib.mkOption {
      type = lib.types.attrsOf lib.types.int;
      default = baseLists.masApps;
      readOnly = true;
      description = "Base list of MAS apps";
    };
    
    # Inheritance options
    useBaseLists = lib.mkOption {
      type = lib.types.bool;
      default = true;
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
    # System packages configuration (replicating your core.nix systemPackages logic)
    environment.systemPackages = lib.mkDefault (
      let
        packageNames = if config.apps.useBaseLists
          then (lib.subtractLists config.apps.systemPackagesToRemove config.apps.baseSystemPackages) ++ config.apps.systemPackagesToAdd
          else config.apps.baseSystemPackages;
        
        # Convert package name strings to actual packages (handling nodePackages.* correctly)
        resolvePackage = name:
          if lib.hasPrefix "nodePackages." name
          then lib.getAttrFromPath (lib.splitString "." name) pkgs
          else lib.getAttr name pkgs;
      in
        map resolvePackage packageNames
    );

    # Environment variables (replicating your core.nix environment setup)
    environment.variables = lib.mkDefault {
      EDITOR = "vim";
      VISUAL = "vim";
    };
    
    # System PATH (replicating your core.nix)
    environment.systemPath = lib.mkDefault [ "/opt/homebrew/bin" ];
    environment.pathsToLink = lib.mkDefault [ "/Applications" ];

    # Homebrew configuration (exactly matching your homebrew.nix structure and logic)
    homebrew = {
      enable = lib.mkDefault true;
      onActivation = {
        autoUpdate = lib.mkDefault true;
        cleanup = lib.mkDefault "zap";
      };
      
      taps = lib.mkDefault [];

      # Global Homebrew settings to reduce sudo requirements (matching your settings)
      global = {
        # Use /opt/homebrew on Apple Silicon, /usr/local on Intel
        brewfile = true;
        lockfiles = false; # Reduce file locking that might need sudo
      };
      
      # Move calculations here to avoid recursion (exactly matching your logic)
      casks = lib.mkDefault (
        if config.apps.useBaseLists
        then (lib.subtractLists config.apps.casksToRemove config.apps.baseCasks) ++ config.apps.casksToAdd
        else config.apps.baseCasks  # Use base list as default
      );
      
      brews = lib.mkDefault (
        if config.apps.useBaseLists
        then (lib.subtractLists config.apps.brewsToRemove config.apps.baseBrews) ++ config.apps.brewsToAdd
        else config.apps.baseBrews  # Use base list as default
      );
      
      masApps = lib.mkDefault (
        let
          finalMasApps = if config.apps.useBaseLists
            then (config.apps.baseMasApps // config.apps.masAppsToAdd) // (lib.genAttrs config.apps.masAppsToRemove (_: null))
            else config.apps.baseMasApps;
        in
          lib.filterAttrs (name: id: id != null) finalMasApps
      );
    };
  };
}