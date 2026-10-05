# modules/darwin/apps/1password.nix
# 1Password SSH agent and CLI integration setup
{ config, lib, pkgs, username, ... }:

let
  # Use full path for 1Password agent socket (tilde doesn't expand in shell quotes)
  onePasswordAgentSocketExpanded = "/Users/${username}/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock";
  symlinkPath = "/Users/${username}/.1password/agent.sock";
  launchAgentPath = "/Users/${username}/Library/LaunchAgents/com.1password.SSH_AUTH_SOCK.plist";

  # LaunchAgent plist content to set SSH_AUTH_SOCK globally
  # Uses expanded path since plist is read by launchd, not shell
  launchAgentPlist = ''
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>Label</key>
      <string>com.1password.SSH_AUTH_SOCK</string>
      <key>ProgramArguments</key>
      <array>
        <string>/bin/sh</string>
        <string>-c</string>
        <string>/bin/launchctl setenv SSH_AUTH_SOCK "${onePasswordAgentSocketExpanded}"</string>
      </array>
      <key>RunAtLoad</key>
      <true/>
    </dict>
    </plist>
  '';
in
{
  # Add 1password-cli to homebrew casks
  apps.casksToAdd = [ "1password-cli" ];

  # Activation script to set up 1Password SSH agent integration
  # Uses extraActivation which is one of the supported activation script names
  system.activationScripts.extraActivation.text = lib.mkAfter ''
    echo "Setting up 1Password SSH agent integration..." >&2

    # Create ~/.1password directory and symlink to agent socket
    if [ ! -d "/Users/${username}/.1password" ]; then
      echo "  Creating ~/.1password directory..." >&2
      mkdir -p "/Users/${username}/.1password"
      chown ${username}:staff "/Users/${username}/.1password"
    fi

    # Create/update symlink to 1Password agent socket
    if [ -L "${symlinkPath}" ]; then
      rm "${symlinkPath}"
    fi
    ln -sf "${onePasswordAgentSocketExpanded}" "${symlinkPath}"
    echo "  Created symlink: ~/.1password/agent.sock -> 1Password agent socket" >&2

    # Create LaunchAgents directory if needed
    if [ ! -d "/Users/${username}/Library/LaunchAgents" ]; then
      mkdir -p "/Users/${username}/Library/LaunchAgents"
      chown ${username}:staff "/Users/${username}/Library/LaunchAgents"
    fi

    # Install LaunchAgent for SSH_AUTH_SOCK
    cat > "${launchAgentPath}" << 'PLIST'
    ${launchAgentPlist}
    PLIST
    chown ${username}:staff "${launchAgentPath}"
    chmod 644 "${launchAgentPath}"
    echo "  Installed LaunchAgent: com.1password.SSH_AUTH_SOCK" >&2

    # Load the LaunchAgent (unload first if already loaded)
    sudo -u ${username} launchctl unload "${launchAgentPath}" 2>/dev/null || true
    sudo -u ${username} launchctl load "${launchAgentPath}" 2>/dev/null || true

    # Set SSH_AUTH_SOCK immediately for this session
    sudo -u ${username} launchctl setenv SSH_AUTH_SOCK "${onePasswordAgentSocketExpanded}" 2>/dev/null || true

    echo "" >&2
    echo "┌──────────────────────────────────────────────────────────────────┐" >&2
    echo "│  1Password Setup - MANUAL STEPS REQUIRED                        │" >&2
    echo "├──────────────────────────────────────────────────────────────────┤" >&2
    echo "│  Open 1Password → Settings → Developer and enable:              │" >&2
    echo "│    ☐ Use the SSH Agent                                          │" >&2
    echo "│    ☐ Integrate with 1Password CLI                               │" >&2
    echo "│                                                                  │" >&2
    echo "│  Then restart your terminal or run:                             │" >&2
    echo "│    export SSH_AUTH_SOCK=~/Library/Group\\ Containers/\\          │" >&2
    echo "│      2BUA8C4S2C.com.1password/t/agent.sock                      │" >&2
    echo "│                                                                  │" >&2
    echo "│  Verify with: ssh-add -l                                        │" >&2
    echo "└──────────────────────────────────────────────────────────────────┘" >&2
  '';
}
