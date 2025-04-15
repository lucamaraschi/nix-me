{ pkgs, config, lib, ... }:

{
  # Mac Mini-specific settings
  
  # Performance optimizations
  system.defaults = {
    # Dock settings optimized for desktop
    dock = {
      autohide = false; # Keep dock visible on a desktop
      tilesize = 48; # Larger icons for desktop display
      magnification = true;
      largesize = 64;
      orientation = "bottom";
    };
    
    # UI settings for desktop use
    finder = {
      CreateDesktop = true; # Show desktop icons
    };
    
    NSGlobalDomain = {
      NSWindowResizeTime = 0.1; # Faster window resizing
      NSAutomaticTermination = false; # Don't auto-terminate apps on desktop
      NSQuitAlwaysKeepsWindows = true; # Keep windows when quitting
    };
  };
  
  # Mac Mini-specific applications
  homebrew.casks = [
    # Media and entertainment apps that make sense on a stationary computer
    "spotify"
    "obs"
    
    # Professional/production tools
    "adobe-creative-cloud"
    "figma"
    
    # Extended development environment
    "docker"
    "orbstack"
    "vmware-fusion"
    
    # Office and productivity for a desktop workstation
    "microsoft-office"
    "microsoft-teams"
  ];
  
  # Mac Mini specific activation scripts
  system.activationScripts.extraActivation.text = ''
    # Set energy settings for desktop use
    echo "Setting energy preferences for Mac Mini..." >&2
    
    # Never sleep the display on a desktop
    pmset displaysleep 0
    
    # Turn on power nap
    pmset powernap 1
    
    # Never sleep the disks
    pmset disksleep 0
    
    # Optimize for performance
    pmset standby 0
  '';
}