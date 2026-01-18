# modules/darwin/apps/hiddenbar.nix
# HiddenBar configuration - clean menu bar with only time visible
{ lib, username, ... }:

{
  # HiddenBar configuration via activation script
  # Uses extraActivation which is a valid nix-darwin activation script name
  system.activationScripts.extraActivation.text = lib.mkAfter ''
    echo "Configuring HiddenBar..." >&2

    # Set HiddenBar preferences for a minimal menu bar
    sudo -u ${username} defaults write com.dwarvesv.hiddenbar isAutoHide -bool true
    sudo -u ${username} defaults write com.dwarvesv.hiddenbar autoHideTimeInterval -int 0  # Immediate hide
    sudo -u ${username} defaults write com.dwarvesv.hiddenbar isLaunchAtLogin -bool true
    sudo -u ${username} defaults write com.dwarvesv.hiddenbar showDockIcon -bool false
    sudo -u ${username} defaults write com.dwarvesv.hiddenbar showPreferences -bool false  # Hide separator when collapsed

    # Minimal visible items - only clock/time related
    # Everything else gets hidden behind HiddenBar's collapse
    sudo -u ${username} defaults write com.dwarvesv.hiddenbar doNotHideTheseApps -array \
      "com.apple.menuextra.clock"

    # Start HiddenBar if not running (for first-time setup)
    if ! pgrep -x "Hidden Bar" > /dev/null 2>&1; then
      echo "  Starting HiddenBar..." >&2
      sudo -u ${username} open -a "Hidden Bar" 2>/dev/null || true
    fi

    echo "  HiddenBar configured - menu bar minimized, only time visible" >&2
  '';
}