{ config, pkgs, lib, ... }:

{
  # Personal profile configuration
  # This module configures the machine for personal use

  apps = {
    useBaseLists = true;

    # Add personal applications
    casksToAdd = [
      # Entertainment
      "spotify"
      "obs"
    ];

    # Remove work-specific apps
    casksToRemove = [
    ];

    # Add personal tools
    systemPackagesToAdd = [
      "yt-dlp"
      "ffmpeg"
      "transmission-cli"
    ];
  };

  # Personal system preferences
  system.defaults = {
    # More relaxed security
    screensaver = {
      askForPassword = true;
      askForPasswordDelay = 300; # 5 minutes
    };

    # Larger dock for easier access
    dock = {
      tilesize = lib.mkForce 48;
    };
  };

  # Personal environment
  environment.variables = {
    PERSONAL_PROJECTS = "$HOME/Projects";
  };
}
