{ pkgs, ... }:

{
  # macOS specific development tools and applications installed via Nix
  environment.systemPackages = with pkgs; [
    # CLI utilities
    jq
    ripgrep
    fd
    eza
    bat
    tree
    htop
    ncdu
    
    # Development tools
    nodejs
    python3
    rustup
    go
    
    # Git tools
    git-lfs
    gh
    
    # Network tools
    nmap
    dnsutils
    mtr
    
    # System tools
    nixpkgs-fmt  # For formatting Nix files
    comma        # Run commands without installing them
    
    # Text processing
    pandoc
    imagemagick
  ];
}