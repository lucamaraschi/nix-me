{ config, pkgs, lib, ... }:

{
  # Work profile configuration
  # This module configures the machine for work use

  apps = {
    useBaseLists = true;

    # Add work-specific applications
    casksToAdd = [
      # Communication & Collaboration
      "linear-linear"
      "loom"
      "microsoft-teams"
      "miro"
      "slack"
      "zoom"

      # Productivity
      "microsoft-office"
      "notion"

      # Creative tools
      "figma"
    ];

    # Remove personal apps
    casksToRemove = [

    ];

    # Add work CLI tools
    systemPackagesToAdd = [
      "terraform"
      "kubectl"
      "helm"
      "awscli2"
      "k3d"
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
