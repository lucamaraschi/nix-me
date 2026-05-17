{ pkgs, config, lib, ... }:

{
  # Bellerofonte - MacBook Pro specific configuration
  # Inherits from macbook-pro base configuration

  imports = [
    # Import MacBook Pro base configuration
    ../../types/macbook-pro/default.nix
  ];

  # Bellerofonte-specific customizations

  apps = {
    useBaseLists = true;

    # Add machine-specific GUI apps
    casksToAdd = [
      # "your-app-here"
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

  projects.repos = {
    # Example:
    # extra-platformatic-repo = {
    #   url = "git@github.com:platformatic/your-repo.git";
    #   path = "src/platformatic/your-repo";
    # };
  };

  # Machine-specific system settings
  # system.defaults = {
  #   # Custom dock size, etc.
  # };
}
