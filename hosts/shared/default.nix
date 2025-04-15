{ pkgs, config, ... }:

{
  # Import common modules
  imports = [
    ../../modules/darwin
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
    
    # Common dock preferences
    dock = {
      autohide = true;
      showhidden = true;
      minimize-to-application = true;
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
    
    # Common command-line tools
    brews = [
      "coreutils"
      "git"
      "jq"
      "ripgrep"
    ];
    
    # Common applications for all machines
    casks = [
      "1password"
      "google-chrome"
      "rectangle"
      "visual-studio-code"
    ];
  };
  
  # Security settings
  security.pam.enableSudoTouchIdAuth = true;
  
  # Common fonts
  fonts.packages = with pkgs; [
    (nerdfonts.override { fonts = [ "FiraCode" "JetBrainsMono" ]; })
    font-awesome
  ];
  
  # Make sure fish is available in all systems
  programs.fish.enable = true;
  environment.shells = with pkgs; [ bash zsh fish ];
}