{ pkgs, config, lib, ... }:

{
  # Nabucodonosor - MacBook specific configuration
  # Inherits from macbook base configuration

  imports = [
    # Import MacBook base configuration
    ../../types/macbook/default.nix
  ];

  # Nabucodonosor-specific customizations
  # Add any machine-specific apps or settings here

  # Example customizations:
  apps = {
    useBaseLists = true;

    # Add machine-specific GUI apps
    casksToAdd = [
      "obs"
      "openscad"               # Streaming/recording
    ];

    # Remove apps you don't need on this machine
    casksToRemove = [
      # "heavy-app-you-dont-use"
    ];

    # Add machine-specific CLI tools
    brewsToAdd = [
      # "your-tool-here"
    ];

    # Add machine-specific Nix packages
    systemPackagesToAdd = [
      # "your-package-here"
    ];
  };

  # Machine-specific system settings
  # system.defaults = {
  #   # Custom dock size, trackpad settings, etc.
  # };
}
