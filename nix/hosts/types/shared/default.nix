{ pkgs, config, lib, ... }:

{
  # Import common modules
  imports = [
    ../../../modules/darwin/default.nix
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
  
  # macOS 27 can reject creation of /etc/pam.d/sudo_local under SIP, even
  # during an administrator activation. Keep this optional integration out of
  # the managed /etc tree so it can never block a system installation.
  security.pam.services.sudo_local.enable = lib.mkDefault false;
  
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
