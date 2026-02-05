# modules/darwin/apps/raycast.nix
# Raycast configuration - replaces Spotlight as the default launcher
{ config, lib, pkgs, username, ... }:

let
  userHome = "/Users/${username}";
  symbolicHotkeysPath = "${userHome}/Library/Preferences/com.apple.symbolichotkeys.plist";
  launchAgentPath = "${userHome}/Library/LaunchAgents/com.raycast.launcher.plist";

  # LaunchAgent to start Raycast at login
  raycastLaunchAgent = ''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.raycast.launcher</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/open</string>
    <string>-a</string>
    <string>Raycast</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>LaunchOnlyOnce</key>
  <true/>
</dict>
</plist>
  '';
in
{
  # Disable Spotlight keyboard shortcuts to free up Cmd+Space for Raycast
  # Key 64 = Show Spotlight search (Cmd+Space)
  # Key 65 = Show Spotlight window (Cmd+Option+Space)
  system.activationScripts.extraActivation.text = lib.mkAfter ''
    echo "Configuring Raycast as default launcher..." >&2

    # Disable Spotlight keyboard shortcuts (run as user, not root!)
    echo "  Disabling Spotlight hotkeys..." >&2

    # Use defaults write with dict-add for more reliable modification on modern macOS
    # Key 64 = Cmd+Space (Show Spotlight search)
    # Key 65 = Cmd+Option+Space (Show Finder search window)
    sudo -u ${username} defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 64 '
      <dict>
        <key>enabled</key>
        <false/>
        <key>value</key>
        <dict>
          <key>parameters</key>
          <array>
            <integer>65535</integer>
            <integer>65535</integer>
            <integer>0</integer>
          </array>
          <key>type</key>
          <string>standard</string>
        </dict>
      </dict>'

    sudo -u ${username} defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 65 '
      <dict>
        <key>enabled</key>
        <false/>
        <key>value</key>
        <dict>
          <key>parameters</key>
          <array>
            <integer>65535</integer>
            <integer>65535</integer>
            <integer>0</integer>
          </array>
          <key>type</key>
          <string>standard</string>
        </dict>
      </dict>'

    # Apply the changes immediately
    sudo -u ${username} /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u 2>/dev/null || true

    # Kill cfprefsd to force reload of preferences (both user and system)
    sudo -u ${username} killall cfprefsd 2>/dev/null || true
    sudo killall cfprefsd 2>/dev/null || true

    # Configure Raycast settings
    echo "  Configuring Raycast preferences..." >&2

    # General settings
    sudo -u ${username} defaults write com.raycast.macos raycastGlobalHotkey -string "Command-49"  # Cmd+Space (49 = space key)
    sudo -u ${username} defaults write com.raycast.macos "NSStatusItem Visible raycastIcon" -bool true

    # Appearance
    sudo -u ${username} defaults write com.raycast.macos raycastPreferredWindowMode -string "default"

    # Launch at login (this sets Raycast's internal preference)
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

    # Create LaunchAgent to ensure Raycast starts at login
    echo "  Installing Raycast LaunchAgent..." >&2

    # Create LaunchAgents directory if needed
    if [ ! -d "${userHome}/Library/LaunchAgents" ]; then
      mkdir -p "${userHome}/Library/LaunchAgents"
      chown ${username}:staff "${userHome}/Library/LaunchAgents"
    fi

    # Install LaunchAgent for Raycast startup
    cat > "${launchAgentPath}" << 'PLIST'
${raycastLaunchAgent}
PLIST
    chown ${username}:staff "${launchAgentPath}"
    chmod 644 "${launchAgentPath}"

    # Load the LaunchAgent (unload first if already loaded)
    sudo -u ${username} launchctl unload "${launchAgentPath}" 2>/dev/null || true
    sudo -u ${username} launchctl load "${launchAgentPath}" 2>/dev/null || true

    echo "  Raycast configured!" >&2
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
    echo "│  LaunchAgent installed: Raycast will start at login             │" >&2
    echo "└──────────────────────────────────────────────────────────────────┘" >&2
  '';
}
