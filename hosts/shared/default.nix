{ pkgs, config, lib, ... }:

{
  # Import common modules
  imports = [
    ../../modules/darwin/default.nix
  ];

  # Base system configuration
  system.defaults = {
    # Common finder preferences
    finder = {
      AppleShowAllExtensions = true;
      FXEnableExtensionChangeWarning = false;
      _FXShowPosixPathInTitle = true;
      ShowPathbar = true;
    };
    
    # Common dock preferences (these can be overridden by machine-specific configs)
    dock = {
      autohide = lib.mkDefault true;
      showhidden = lib.mkDefault true;
      minimize-to-application = lib.mkDefault true;
      tilesize = lib.mkDefault 20; # Default size, can be overridden
    };
    
    # Common global domain preferences
    NSGlobalDomain = {
      AppleInterfaceStyle = "Dark";
      AppleShowAllExtensions = true;
      NSDocumentSaveNewDocumentsToCloud = false;
      NSAutomaticCapitalizationEnabled = false;
      NSAutomaticSpellingCorrectionEnabled = false;
    };
  };
  
  # Shared homebrew packages
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      cleanup = "zap";
    };
    
    # Homebrew taps
    taps = [
    ];
    
    # Command-line tools
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
      "mas"  # Mac App Store CLI
      "pnpm"
      "ripgrep"
      "terraform"
      "trash"
    ];
    
    # macOS applications (common to all machine types)
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
  };
  
  # Security settings
  security.pam.services.sudo_local.touchIdAuth = true;
  
  # Common fonts
  fonts.packages = with pkgs; [
    nerd-fonts.fira-code
    nerd-fonts.jetbrains-mono
    
    font-awesome
  ];
  
  # Make sure fish is available in all systems
  programs.fish.enable = true;
  environment.shells = with pkgs; [ bash zsh fish ];
}