# Work profile
# Adds collaboration, communication, and enterprise tools
# Typically combined with dev.nix for development work
{ config, pkgs, lib, ... }:

{
  apps = {
    useBaseLists = true;

    # Work GUI applications
    casksToAdd = [
      # Communication & Collaboration
      "slack"
      "zoom"
      "microsoft-teams"
      "loom"              # Video messaging
      "miro"              # Whiteboarding
      "linear-linear"     # Project management

      # Productivity
      "microsoft-office"
      "notion"

      # Design collaboration
      "figma"
    ];

    # Work CLI tools (infrastructure/cloud)
    systemPackagesToAdd = [
      "terraform"
      "kubectl"
      "helm"
      "awscli2"
    ];

    # Work MAS apps
    # masAppsToAdd = {
    #   "Keynote" = 409183694;
    # };
  };

  # Work-specific system preferences
  system.defaults = {
    # Stricter security for work
    screensaver = {
      askForPassword = true;
      askForPasswordDelay = 5; # Lock quickly (5 seconds)
    };

    # Disable potentially distracting features
    NSGlobalDomain = {
      NSAutomaticCapitalizationEnabled = false;
      NSAutomaticSpellingCorrectionEnabled = false;
    };
  };

  # Work-specific environment
  environment.variables = {
    WORK_ENV = "production";
  };
}
