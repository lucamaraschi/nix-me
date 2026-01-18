# modules/darwin/apps/raycast.nix
# Raycast configuration - replaces Spotlight as the default launcher
{ config, lib, pkgs, username, ... }:

{
  # Disable Spotlight keyboard shortcuts to free up Cmd+Space for Raycast
  # Key 64 = Show Spotlight search (Cmd+Space)
  # Key 65 = Show Spotlight window (Cmd+Option+Space)
  system.activationScripts.extraActivation.text = lib.mkAfter ''
    echo "Configuring Raycast as default launcher..." >&2

    # Disable Spotlight keyboard shortcuts
    echo "  Disabling Spotlight hotkeys..." >&2

    # Disable Cmd+Space for Spotlight
    /usr/libexec/PlistBuddy -c "Delete :AppleSymbolicHotKeys:64" ~/Library/Preferences/com.apple.symbolichotkeys.plist 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :AppleSymbolicHotKeys:64:enabled bool false" ~/Library/Preferences/com.apple.symbolichotkeys.plist 2>/dev/null || true

    # Disable Cmd+Option+Space for Spotlight window
    /usr/libexec/PlistBuddy -c "Delete :AppleSymbolicHotKeys:65" ~/Library/Preferences/com.apple.symbolichotkeys.plist 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :AppleSymbolicHotKeys:65:enabled bool false" ~/Library/Preferences/com.apple.symbolichotkeys.plist 2>/dev/null || true

    # Apply the changes immediately
    /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u 2>/dev/null || true

    # Configure Raycast settings
    echo "  Configuring Raycast preferences..." >&2

    # General settings
    sudo -u ${username} defaults write com.raycast.macos raycastGlobalHotkey -string "Command-49"  # Cmd+Space (49 = space key)
    sudo -u ${username} defaults write com.raycast.macos "NSStatusItem Visible raycastIcon" -bool true

    # Appearance
    sudo -u ${username} defaults write com.raycast.macos raycastPreferredWindowMode -string "default"

    # Launch at login
    sudo -u ${username} defaults write com.raycast.macos openAtLogin -bool true

    # Enable clipboard history
    sudo -u ${username} defaults write com.raycast.macos "ToggleClipboardHistoryHotkey" -string "Command-Shift-86"  # Cmd+Shift+V

    # Floating notes hotkey
    sudo -u ${username} defaults write com.raycast.macos "ToggleFloatingNotesHotkey" -string "Command-Shift-78"  # Cmd+Shift+N

    # Window management hotkeys (like Rectangle but built-in)
    sudo -u ${username} defaults write com.raycast.macos "WindowLeftHalfHotkey" -string "Control-Option-37"    # Ctrl+Opt+Left
    sudo -u ${username} defaults write com.raycast.macos "WindowRightHalfHotkey" -string "Control-Option-39"   # Ctrl+Opt+Right
    sudo -u ${username} defaults write com.raycast.macos "WindowMaximizeHotkey" -string "Control-Option-36"    # Ctrl+Opt+Return

    # Confetti celebration (for fun!)
    sudo -u ${username} defaults write com.raycast.macos showConfettiAnimationOnExtensionRun -bool true

    echo "  Raycast configured! Restart Raycast or log out/in for hotkey changes." >&2
    echo "" >&2
    echo "┌──────────────────────────────────────────────────────────────────┐" >&2
    echo "│  Raycast Setup Complete                                         │" >&2
    echo "├──────────────────────────────────────────────────────────────────┤" >&2
    echo "│  Hotkeys configured:                                            │" >&2
    echo "│    Cmd+Space        → Open Raycast (Spotlight disabled)         │" >&2
    echo "│    Cmd+Shift+V      → Clipboard History                         │" >&2
    echo "│    Cmd+Shift+N      → Floating Notes                            │" >&2
    echo "│    Ctrl+Opt+←/→     → Window Left/Right Half                    │" >&2
    echo "│    Ctrl+Opt+Return  → Maximize Window                           │" >&2
    echo "│                                                                  │" >&2
    echo "│  Tip: Open Raycast and explore Extensions for more features!    │" >&2
    echo "└──────────────────────────────────────────────────────────────────┘" >&2
  '';
}
