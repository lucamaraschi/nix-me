# modules/home-manager/rectangle.nix
{ config, lib, pkgs, ... }:

{
  # Rectangle window manager configuration
  home.file.".config/rectangle/RectangleConfig.json".text = builtins.toJSON {
    # General settings
    SUEnableAutomaticChecks = true;
    launchOnLogin = true;
    hideMenubarIcon = false;
    alternateDefaultShortcuts = true;
    allowAnyShortcut = true;
    
    # Window behavior
    gapSize = 5;
    snapEdgeMarginTop = 5;
    snapEdgeMarginBottom = 5;
    snapEdgeMarginLeft = 5;
    snapEdgeMarginRight = 5;
    
    # Size settings
    centerHalfCycles = [
      "50"
      "67"
      "75"
    ];
    centeredDirectionalMove = false;
    almostMaximizeHeight = 95;
    almostMaximizeWidth = 95;
    
    # Appearance
    windowSnapping = true;
    todoMode = false;
    
    # Keyboard shortcuts (using Hyper key (Cmd+Ctrl+Alt+Shift) for most operations)
    shortcuts = {
      # Basic positioning
      leftHalf = "^⌥⌘←";            # Ctrl+Option+Cmd+Left
      rightHalf = "^⌥⌘→";           # Ctrl+Option+Cmd+Right
      topHalf = "^⌥⌘↑";             # Ctrl+Option+Cmd+Up
      bottomHalf = "^⌥⌘↓";          # Ctrl+Option+Cmd+Down
      
      # Corners
      topLeft = "^⌥⌘U";             # Ctrl+Option+Cmd+U
      topRight = "^⌥⌘I";            # Ctrl+Option+Cmd+I
      bottomLeft = "^⌥⌘J";          # Ctrl+Option+Cmd+J
      bottomRight = "^⌥⌘K";         # Ctrl+Option+Cmd+K
      
      # Thirds
      leftThird = "^⌥⌘D";           # Ctrl+Option+Cmd+D
      centerThird = "^⌥⌘F";         # Ctrl+Option+Cmd+F
      rightThird = "^⌥⌘G";          # Ctrl+Option+Cmd+G
      
      # Full screen operations
      maximize = "^⌥⌘M";            # Ctrl+Option+Cmd+M
      maximizeHeight = "^⌥⌘H";      # Ctrl+Option+Cmd+H
      
      # Center operations
      center = "^⌥⌘C";              # Ctrl+Option+Cmd+C
      centerHalf = "^⌥⌘V";          # Ctrl+Option+Cmd+V
      
      # Screen movement
      nextDisplay = "^⌥⌘]";         # Ctrl+Option+Cmd+]
      previousDisplay = "^⌥⌘[";     # Ctrl+Option+Cmd+[
      
      # Size adjustments
      restore = "^⌥⌘=";             # Ctrl+Option+Cmd+=
      smaller = "^⌥⌘-";             # Ctrl+Option+Cmd+-
      larger = "^⌥⌘+";              # Ctrl+Option+Cmd++
    };
    
    # List of apps to ignore
    appsIgnored = [
      "com.apple.ActivityMonitor"
      "com.apple.DigitalColorMeter"
      "com.apple.systempreferences"
      "com.apple.finder"
    ];
  };
}