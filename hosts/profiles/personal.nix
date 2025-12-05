# Personal profile
# Adds entertainment, media, and personal productivity apps
# Can be combined with other profiles (dev, work)
{ config, pkgs, lib, ... }:

{
  apps = {
    useBaseLists = true;

    # Personal GUI applications
    casksToAdd = [
      # Entertainment & Media
      "spotify"
      "obs"               # Streaming/recording

      # Creative
      # "figma"
      # "adobe-creative-cloud"
    ];

    # Personal CLI tools
    systemPackagesToAdd = [
      "yt-dlp"            # Video downloader
      "ffmpeg"            # Media processing
    ];

    # Personal MAS apps
    masAppsToAdd = {
      "iA-Writer" = 775737590;
      "PDF-Expert" = 1055273043;
    };
  };

  # Personal system preferences
  system.defaults = {
    # More relaxed security for personal use
    screensaver = {
      askForPassword = true;
      askForPasswordDelay = 300; # 5 minutes grace period
    };
  };

  # Personal environment
  environment.variables = {
    PERSONAL_PROJECTS = "$HOME/Projects";
  };
}
