{ pkgs, config, lib, ... }:

{
  # Zion - Mac Mini maker/craft station
  # Named after the last human city in The Matrix trilogy

  imports = [
    # Import Mac Mini base configuration
    ../../types/macmini/default.nix
  ];

  # Maker/craft specific applications
  apps = {
    useBaseLists = true;

    # 3D printing and design apps
    casksToAdd = [
      # Streaming/Recording
      "elgato-camera-hub"     # Elgato Prompter & camera controls

      # Manual installs required (not in Homebrew):
      # - Cricut Design Space: https://design.cricut.com/
      # - Blackmagic ATEM Software Control: https://www.blackmagicdesign.com/support/family/atem-live-production-switchers
    ];

    # Design-related CLI tools
    systemPackagesToAdd = [
    ];
  };

  # Environment for maker projects
  environment.variables = {
    MAKER_PROJECTS = "$HOME/Maker";
  };
}
