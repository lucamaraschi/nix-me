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