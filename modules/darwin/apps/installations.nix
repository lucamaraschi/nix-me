# Centralized app installation management
# This defines the MINIMAL base - productivity essentials only
# Development tools, work apps, and personal apps are in profiles
{ config, lib, pkgs, ... }:

let
  # Define base lists - these are the MINIMAL essentials
  # Development-specific tools are in hosts/profiles/dev.nix
  baseLists = {
    # System packages via Nix - minimal essentials
    systemPackages = [
      # Core utilities
      "ripgrep"
      "fd"
      "eza"
      "bat"
      "tree"
      "htop"
      "ncdu"
      "jq"

      # Nix tooling
      "nixpkgs-fmt"
      "nil"  # Nix language server
      "comma"
    ];

    # GUI applications via Homebrew casks - minimal essentials
    casks = [
      # Password & Security
      "1password"

      # Productivity & Utilities
      "hiddenbar"
      "raycast"
      "rectangle"
      "hammerspoon"
      "ghostty"           # Modern terminal

      # Privacy
      "proton-mail"
      "protonvpn"

      # Browsers
      "google-chrome"
    ];

    # CLI tools via Homebrew - minimal essentials
    brews = [
      "coreutils"
      "direnv"
      "git"
      "grep"
      "mas"
      "trash"
    ];

    # Mac App Store applications - minimal essentials
    masApps = {
      Tailscale = 1475387142;
      "PDF-Expert" = 1055273043;
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

    # Homebrew options
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
    # System packages configuration
    environment.systemPackages = lib.mkDefault (
      let
        packageNames = if config.apps.useBaseLists
          then (lib.subtractLists config.apps.systemPackagesToRemove config.apps.baseSystemPackages) ++ config.apps.systemPackagesToAdd
          else config.apps.baseSystemPackages;

        # Convert package name strings to actual packages
        resolvePackage = name:
          if lib.hasPrefix "nodePackages." name
          then lib.getAttrFromPath (lib.splitString "." name) pkgs
          else lib.getAttr name pkgs;
      in
        map resolvePackage packageNames
    );

    # Environment variables
    environment.variables = lib.mkDefault {
      EDITOR = "vim";
      VISUAL = "vim";
    };

    # System PATH
    environment.systemPath = lib.mkDefault [ "/opt/homebrew/bin" ];
    environment.pathsToLink = lib.mkDefault [ "/Applications" ];

    # Homebrew configuration
    homebrew = {
      enable = lib.mkDefault true;
      onActivation = {
        autoUpdate = lib.mkDefault true;
        cleanup = lib.mkDefault "zap";
      };

      taps = lib.mkDefault [];

      global = {
        brewfile = true;
        lockfiles = false;
      };

      casks = lib.mkDefault (
        if config.apps.useBaseLists
        then (lib.subtractLists config.apps.casksToRemove config.apps.baseCasks) ++ config.apps.casksToAdd
        else config.apps.baseCasks
      );

      brews = (
        if config.apps.useBaseLists
        then (lib.subtractLists config.apps.brewsToRemove config.apps.baseBrews) ++ config.apps.brewsToAdd
        else config.apps.baseBrews
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
