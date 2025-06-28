# modules/darwin/hiddenbar.nix
{ lib, ... }:

{
  # HiddenBar configuration via system defaults
  system.defaults.CustomUserPreferences = {
    # HiddenBar settings
    "com.dwarvesv.hiddenbar" = {
      # Auto-hide menu bar items when not needed
      isAutoHide = true;
      
      # Hide after X seconds of inactivity
      autoHideTimeInterval = 3;
      
      # Show separator between hidden and visible items
      showPreferences = true;
      
      # Don't hide specific important items (example list)
      # You'll need to find the bundle IDs of apps you want to keep visible
      doNotHideTheseApps = [
        "com.apple.controlcenter"     # Control Center
        "com.apple.systemuiserver"    # System UI elements
        # Add more bundle IDs as needed
      ];
      
      # Launch at login
      isLaunchAtLogin = true;
      
      # Show in dock
      showDockIcon = false;
      
      # Segment count (how many items to show/hide)
      numberOfSegment = 1;
    };
  };
  
  # Alternative: Use activation script for more complex configuration
  system.activationScripts.hiddenBarConfig.text = ''
    echo "Configuring HiddenBar..." >&2
    
    # Wait for user session and HiddenBar to be available
    if [ -n "$USER" ] && [ "$USER" != "root" ]; then
      # Set HiddenBar preferences
      sudo -u "$USER" defaults write com.dwarvesv.hiddenbar isAutoHide -bool true
      sudo -u "$USER" defaults write com.dwarvesv.hiddenbar autoHideTimeInterval -int 3
      sudo -u "$USER" defaults write com.dwarvesv.hiddenbar isLaunchAtLogin -bool true
      sudo -u "$USER" defaults write com.dwarvesv.hiddenbar showDockIcon -bool false
      sudo -u "$USER" defaults write com.dwarvesv.hiddenbar showPreferences -bool true
      
      # Configure which apps to keep visible (example)
      # You might need to adjust these based on what you want to keep visible
      sudo -u "$USER" defaults write com.dwarvesv.hiddenbar doNotHideTheseApps -array \
        "com.apple.controlcenter" \
        "com.apple.systemuiserver" \
        "com.1password.1password-macos" \
        "com.apple.spotlight"
      
      echo "HiddenBar configured successfully" >&2
    fi
  '';
}