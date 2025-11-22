# modules/shared/packages.nix
# Cross-platform CLI tools that work on both Darwin and Linux
#
# NOTE: This file is currently NOT imported anywhere. It's kept as a reference
# for package lists that could be used in the future. The actual package
# configuration is in modules/darwin/apps/installations.nix
#
{ pkgs, ... }:

{
  # Common development tools available on all platforms
  commonPackages = with pkgs; [
    # Core utilities
    jq
    ripgrep
    fd
    eza
    bat
    tree
    htop
    ncdu

    # Development languages
    nodejs_22  # npm bundled
    python3
    rustup
    go

    # Version control and collaboration
    gh
    git

    # Network tools
    nmap
    mtr

    # Nix tools
    nixpkgs-fmt
    comma

    # Document processing
    pandoc
    imagemagick

    # Kubernetes
    kubectl
    k3d
    helm

    # Modern shell tools
    fzf
    starship
    zoxide
    direnv
  ];

  # Additional tools for development VMs
  vmDevPackages = with pkgs; [
    # Text editors
    neovim
    vim

    # File management
    trash-cli

    # Process monitoring
    bottom  # btm
    procs

    # Network debugging
    curl
    wget
    httpie

    # Archive tools
    unzip
    zip
    p7zip

    # JSON/YAML tools
    yq-go

    # Container tools
    docker-compose
  ];
}
