{ pkgs, config, lib, ... }:

{
  # MacBook-specific settings
  
  # Battery/power management
  system.defaults = {
    # Trackpad settings for laptops
    trackpad = {
      Clicking = true;
      TrackpadRightClick = true;
      TrackpadThreeFingerDrag = true;
      ActuationStrength = 1; # Lighter click force
    };

    # Dock settings for laptops (smaller icons to save space)
    dock = {
      tilesize = lib.mkForce 32; # Smaller icons for laptop screens
    };
    
    # # Energy saving preferences
    # NSGlobalDomain = {
    #   # NSAutomaticTermination = true; # Auto-terminate inactive apps
    #   NSQuitAlwaysKeepsWindows = false; # Don't keep windows when quitting
    # };
    
    # Custom power management settings
    CustomUserPreferences = {
      "~/Library/Preferences/ByHost/com.apple.controlcenter".BatteryShowPercentage = true;
    };
  };

  # Power management scripts
  system.activationScripts.macbookOptimization.text = ''
    # Set energy saving preferences for laptops
    echo "Setting energy preferences for MacBook..." >&2
    
    # Set display sleep to 15 minutes on battery, 30 minutes on power
    pmset -b displaysleep 15
    pmset -c displaysleep 30
    
    # Enable power nap on power adapter only
    pmset -b powernap 0
    pmset -c powernap 1
    
    # Other power-saving settings
    pmset -b disksleep 10
    pmset -c disksleep 0
  '';
}