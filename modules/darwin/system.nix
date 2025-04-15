# modules/darwin/system.nix
{ lib, ... }:

{
  # macOS system preferences - all defaults that can be overridden by machine-specific configs
  system.defaults = {
    # Dock preferences
    dock = {
      autohide = lib.mkDefault true;
      show-recents = lib.mkDefault false;
      static-only = lib.mkDefault true;
      tilesize = lib.mkDefault 20;
      mineffect = lib.mkDefault "scale";
      minimize-to-application = lib.mkDefault true;
      orientation = lib.mkDefault "bottom";
      showhidden = lib.mkDefault true;
    };
    
    # Finder preferences
    finder = {
      AppleShowAllExtensions = lib.mkDefault true;
      AppleShowAllFiles = lib.mkDefault true;
      FXEnableExtensionChangeWarning = lib.mkDefault false;
      QuitMenuItem = lib.mkDefault true;
      _FXShowPosixPathInTitle = lib.mkDefault true;
      CreateDesktop = lib.mkDefault false; # Default to hide desktop icons
      ShowPathbar = lib.mkDefault true;
      ShowStatusBar = lib.mkDefault true;
    };
    
    # Login window settings
    loginwindow = {
      GuestEnabled = lib.mkDefault false;
      DisableConsoleAccess = lib.mkDefault true;
    };
    
    # Launch Services
    LaunchServices.LSQuarantine = lib.mkDefault true;
    
    # Power management
    menuExtraClock.ShowSeconds = lib.mkDefault true;
    screencapture.location = lib.mkDefault "~/Pictures/Screenshots";
    
    # Software Update
    SoftwareUpdate = {
      AutomaticallyInstallMacOSUpdates = lib.mkDefault true;
    };
    
    # Global preferences
    NSGlobalDomain = {
      # Appearance
      AppleInterfaceStyle = lib.mkDefault "Dark";
      AppleShowAllExtensions = lib.mkDefault true;
      AppleShowAllFiles = lib.mkDefault true;
      
      # Keyboard and input
      AppleKeyboardUIMode = lib.mkDefault 3;
      ApplePressAndHoldEnabled = lib.mkDefault false;
      InitialKeyRepeat = lib.mkDefault 15;
      KeyRepeat = lib.mkDefault 2;
      
      # Document behavior
      NSDocumentSaveNewDocumentsToCloud = lib.mkDefault false;
      
      # Text behavior
      NSAutomaticCapitalizationEnabled = lib.mkDefault false;
      NSAutomaticDashSubstitutionEnabled = lib.mkDefault false;
      NSAutomaticPeriodSubstitutionEnabled = lib.mkDefault false;
      NSAutomaticQuoteSubstitutionEnabled = lib.mkDefault false;
      NSAutomaticSpellingCorrectionEnabled = lib.mkDefault false;
      
      # UI behavior
      NSNavPanelExpandedStateForSaveMode = lib.mkDefault true;
      NSNavPanelExpandedStateForSaveMode2 = lib.mkDefault true;
      
      # Misc
      _HIHideMenuBar = lib.mkDefault false;
    };
    
    # Trackpad - defaults that can be overridden by machine-specific configs
    trackpad = {
      Clicking = lib.mkDefault true;
      TrackpadRightClick = lib.mkDefault true;
      TrackpadThreeFingerDrag = lib.mkDefault true;
    };
    
    # Custom preferences
    CustomUserPreferences = lib.mkDefault {
      "~/Library/Preferences/ByHost/com.apple.controlcenter".BatteryShowPercentage = true;
      "com.apple.AdLib".allowApplePersonalizedAdvertising = false;
      "com.apple.WindowManager".GloballyEnabled = true;
    };
  };
  
  # Firewall settings
  system.defaults.alf = {
    globalstate = lib.mkDefault 1; # on for specific services
    allowsignedenabled = lib.mkDefault 1;
    allowdownloadsignedenabled = lib.mkDefault 1;
  };
}