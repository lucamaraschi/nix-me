{ config, pkgs, lib, ... }:

{
  # Work profile configuration
  # This module configures the machine for work use

  apps = {
    useBaseLists = true;

    # Add work-specific applications
    casksToAdd = [
      # Communication
      "microsoft-teams"
      "slack"
      "zoom"

      # Productivity
      "microsoft-office"
      "linear-linear"

      # Development (work tools)
      "docker-desktop"
      "visual-studio-code"
      "postman"
    ];

    # Remove personal apps
    casksToRemove = [
      "spotify"
      "obs"
    ];

    # Add work CLI tools
    systemPackagesToAdd = [
      "terraform"
      "kubectl"
      "helm"
      "awscli2"
    ];
  };

  # Work-specific system preferences
  system.defaults = {
    # Stricter security for work
    screensaver = {
      askForPassword = true;
      askForPasswordDelay = 5; # Lock after 5 seconds
    };

    # Disable analytics/telemetry
    NSGlobalDomain = {
      NSAutomaticCapitalizationEnabled = false;
      NSAutomaticSpellingCorrectionEnabled = false;
    };
  };

  # Work-specific environment
  environment.variables = {
    WORK_ENV = "production";
    # Add company-specific variables
  };
}
