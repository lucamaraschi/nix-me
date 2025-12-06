# Development profile
# Adds development tools, IDEs, and programming languages
# Can be combined with other profiles (work, personal)
{ config, pkgs, lib, ... }:

{
  apps = {
    useBaseLists = true;

    # Development GUI applications
    casksToAdd = [
      # IDEs & Editors
      "visual-studio-code"

      # Development tools
      "docker-desktop"
      "orbstack"          # Lightweight Docker/Linux VMs
      "github"            # GitHub Desktop

      # API & Database
      # "postman"
      # "tableplus"

      # Virtualization
      "utm"
      "virtualbuddy"
    ];

    # Development CLI tools via Homebrew
    brewsToAdd = [
      "fd"
      "gcc"
      "jq"
      "k3d"               # Local Kubernetes
    ];

    # Development packages via Nix
    systemPackagesToAdd = [
      # Languages & Runtimes
      "nodejs_22"
      "nodePackages.pnpm"
      "nodePackages.npm"
      "nodePackages.typescript"
      "python3"
      "rustup"
      "go"

      # Development utilities
      "gh"                # GitHub CLI
      "pandoc"
      "imagemagick"

      # Network debugging
      "nmap"
      "dnsutils"
      "mtr"
    ];

    # Development MAS apps
    masAppsToAdd = {
      Xcode = 497799835;
    };
  };

  # Development-specific environment
  environment.variables = {
    # Node.js
    NODE_ENV = "development";

    # Go
    GOPATH = "$HOME/go";

    # Rust
    CARGO_HOME = "$HOME/.cargo";
  };
}
