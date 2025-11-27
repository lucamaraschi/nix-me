{ pkgs, config, lib, ... }:

{
  # Mac Mini-specific settings
  
  # Performance optimizations
  system.defaults = {
    # Dock settings optimized for desktop
    dock = {
      autohide = lib.mkForce false; # Keep dock visible on a desktop
      tilesize = lib.mkForce 48; # Larger icons for desktop display
      magnification = lib.mkForce true;
      largesize = lib.mkForce 64;
      orientation = lib.mkForce "bottom";
    };
    
    # UI settings for desktop use
    finder = {
      CreateDesktop = lib.mkForce true; # Show desktop icons
    };
    
    # NSGlobalDomain = {
    #   NSWindowResizeTime = 0.1; # Faster window resizing
    #   # NSAutomaticTermination = false; # Don't auto-terminate apps on desktop
    #   NSQuitAlwaysKeepsWindows = true; # Keep windows when quitting
    # };
  };
  
  # Mac Mini-specific applications
  apps = {
    useBaseLists = true;
    casksToRemove = [];
    casksToAdd = [
      # Media and entertainment apps that make sense on a stationary computer
      "spotify"
      "obs"
      
      # Professional/production tools
      "adobe-creative-cloud"
      "figma"
      
      # Extended development environment
      "docker"
      "orbstack"
      # "vmware-fusion" # Disabled in Homebrew - requires manual install from VMware

      # Office and productivity for a desktop workstation
      "microsoft-office"
      "microsoft-teams"
    ];
  };
  homebrew.casks = 
  
  # Mac Mini specific activation scripts
  system.activationScripts.macminiOptimization.text = ''
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