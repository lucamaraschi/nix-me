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
    LaunchServices.LSQuarantine = lib.mkDefault false;

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
      # Use proper user preference path instead of ByHost
      "com.apple.controlcenter".BatteryShowPercentage = true;
      "com.apple.AdLib".allowApplePersonalizedAdvertising = false;
      "com.apple.WindowManager".GloballyEnabled = true;
    };
  };

  # Firewall settings
  networking.applicationFirewall = {
    allowSignedApp = lib.mkDefault true;
    allowSigned = lib.mkDefault true;
    enable = lib.mkDefault true;
    blockAllIncoming = lib.mkDefault false;  # globalstate = 1 means firewall on but not blocking all
  };

  # Extend sudo timeout to reduce password prompts during long operations
  security.sudo = {
    # Keep sudo authentication for 60 minutes instead of default 5 minutes
    extraConfig = ''
      # Extend sudo timeout for better user experience during Homebrew installs
      Defaults timestamp_timeout=60

      # Allow sudo to work with Touch ID properly
      Defaults !tty_tickets
    '';
  };

  system.activationScripts.postActivation.text = ''
    echo "Disabling Gatekeeper for VM environment..."
    sudo spctl --master-disable 2>/dev/null || true

    # Also disable quarantine attribute on apps
    sudo xattr -r -d com.apple.quarantine /Applications 2>/dev/null || true
  '';
}
