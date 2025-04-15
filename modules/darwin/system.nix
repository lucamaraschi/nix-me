{ ... }:

{
  # macOS system preferences
  system.defaults = {
    # Dock preferences
    dock = {
      autohide = true;
      show-recents = false;
      static-only = true;
      tilesize = 20;
      mineffect = "scale";
      minimize-to-application = true;
      orientation = "bottom";
      showhidden = true;
    };
    
    # Finder preferences
    finder = {
      AppleShowAllExtensions = true;
      AppleShowAllFiles = true;
      FXEnableExtensionChangeWarning = false;
      QuitMenuItem = true;
      _FXShowPosixPathInTitle = true;
      CreateDesktop = false; # Hide desktop icons
      ShowPathbar = true;
      ShowStatusBar = true;
    };
    
    # Login window settings
    loginwindow = {
      GuestEnabled = false;
      DisableConsoleAccess = true;
    };
    
    # Launch Services
    LaunchServices.LSQuarantine = true;
    
    # Power management
    menuExtraClock.ShowSeconds = true;
    screencapture.location = "~/Pictures/Screenshots";
    
    # Software Update
    SoftwareUpdate = {
      AutomaticallyInstallMacOSUpdates = true;
    };
    
    # Global preferences
    NSGlobalDomain = {
      # Appearance
      AppleInterfaceStyle = "Dark";
      AppleShowAllExtensions = true;
      AppleShowAllFiles = true;
      
      # Keyboard and input
      AppleKeyboardUIMode = 3;
      ApplePressAndHoldEnabled = false;
      InitialKeyRepeat = 15;
      KeyRepeat = 2;
      
      # Document behavior
      NSDocumentSaveNewDocumentsToCloud = false;
      
      # Text behavior
      NSAutomaticCapitalizationEnabled = false;
      NSAutomaticDashSubstitutionEnabled = false;
      NSAutomaticPeriodSubstitutionEnabled = false;
      NSAutomaticQuoteSubstitutionEnabled = false;
      NSAutomaticSpellingCorrectionEnabled = false;
      
      # UI behavior
      NSNavPanelExpandedStateForSaveMode = true;
      NSNavPanelExpandedStateForSaveMode2 = true;
      
      # Misc
      _HIHideMenuBar = false;
    };
    
    # Trackpad
    trackpad = {
      Clicking = true;
      TrackpadRightClick = true;
      TrackpadThreeFingerDrag = true;
    };
    
    # Transparency
    universalaccess = {
      reduceTransparency = true;
    };
    
    # Custom preferences
    CustomUserPreferences = {
      "~/Library/Preferences/ByHost/com.apple.controlcenter".BatteryShowPercentage = true;
      "com.apple.AdLib".allowApplePersonalizedAdvertising = false;
      "com.apple.WindowManager".GloballyEnabled = true;
    };
  };
  
  # Firewall settings
  system.defaults.alf = {
    globalstate = 1; # on for specific services
    allowsignedenabled = 1;
    allowdownloadsignedenabled = 1;
  };
}