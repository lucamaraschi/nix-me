# modules/home-manager/rectangle.nix
# Rectangle window manager configuration for macOS
# Uses macOS defaults system (plist) instead of JSON config
{ config, lib, pkgs, ... }:

{
  # Rectangle preferences via activation script
  # Rectangle stores settings in ~/Library/Preferences/com.knollsoft.Rectangle.plist
  home.activation.rectangleConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    # General settings
    $DRY_RUN_CMD /usr/bin/defaults write com.knollsoft.Rectangle SUEnableAutomaticChecks -bool true
    $DRY_RUN_CMD /usr/bin/defaults write com.knollsoft.Rectangle launchOnLogin -bool true
    $DRY_RUN_CMD /usr/bin/defaults write com.knollsoft.Rectangle hideMenubarIcon -bool false
    $DRY_RUN_CMD /usr/bin/defaults write com.knollsoft.Rectangle alternateDefaultShortcuts -bool true
    $DRY_RUN_CMD /usr/bin/defaults write com.knollsoft.Rectangle allowAnyShortcut -bool true

    # Window behavior - gap size
    $DRY_RUN_CMD /usr/bin/defaults write com.knollsoft.Rectangle gapSize -float 5
    $DRY_RUN_CMD /usr/bin/defaults write com.knollsoft.Rectangle snapEdgeMarginTop -int 5
    $DRY_RUN_CMD /usr/bin/defaults write com.knollsoft.Rectangle snapEdgeMarginBottom -int 5
    $DRY_RUN_CMD /usr/bin/defaults write com.knollsoft.Rectangle snapEdgeMarginLeft -int 5
    $DRY_RUN_CMD /usr/bin/defaults write com.knollsoft.Rectangle snapEdgeMarginRight -int 5

    # Window snapping
    $DRY_RUN_CMD /usr/bin/defaults write com.knollsoft.Rectangle windowSnapping -int 2

    # Almost maximize settings (percentage)
    $DRY_RUN_CMD /usr/bin/defaults write com.knollsoft.Rectangle almostMaximizeHeight -float 0.95
    $DRY_RUN_CMD /usr/bin/defaults write com.knollsoft.Rectangle almostMaximizeWidth -float 0.95

    # Cycling behavior
    $DRY_RUN_CMD /usr/bin/defaults write com.knollsoft.Rectangle subsequentExecutionMode -int 1
  '';

}
