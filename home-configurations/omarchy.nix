# home-configurations/omarchy.nix
# Standalone home-manager configuration for Omarchy (Arch Linux + Hyprland)
# This layers nix-me configs on top of DHH's Omarchy setup
{ config, pkgs, lib, ... }:

let
  sharedPackages = import ../modules/shared/packages.nix { inherit pkgs; };
in
{
  home.username = lib.mkDefault "dev";
  home.homeDirectory = lib.mkDefault "/home/dev";
  home.stateVersion = "23.11";

  # Import shared modules
  imports = [
    # Cross-platform modules
    ../modules/home-manager/apps/git.nix
    ../modules/home-manager/apps/tmux.nix
    ../modules/home-manager/shell/direnv.nix

    # Linux-specific fish configuration
    ../modules/nixos/fish.nix
  ];

  # Additional packages via Nix (complements Omarchy's pacman packages)
  home.packages = with pkgs;
    sharedPackages.commonPackages
    ++ [
      # Kubernetes (likely not in Omarchy by default)
      kubectl
      k3d
      helm

      # Additional dev tools
      gh
      lazygit
      delta
      difftastic

      # Terminal utilities
      tldr
      navi

      # System info
      fastfetch

      # JSON/Data tools
      fx
      gron
      yq-go

      # Process management
      bottom
      procs

      # Git tools
      git-lfs
      pre-commit
    ];

  # Starship prompt (enhances Omarchy's default)
  programs.starship = {
    enable = true;
    settings = {
      add_newline = false;
      character = {
        success_symbol = "[❯](bold green)";
        error_symbol = "[❯](bold red)";
      };
      git_branch = {
        symbol = " ";
      };
      directory = {
        truncation_length = 3;
        truncate_to_repo = true;
      };
      kubernetes = {
        disabled = false;
        symbol = "⎈ ";
      };
      nix_shell = {
        disabled = false;
        symbol = " ";
      };
    };
  };

  # Fish as an alternative shell (Omarchy uses Zsh by default)
  # User can switch with: chsh -s $(which fish)
  programs.fish.shellAliases = lib.mkForce {
    # Arch Linux system management (overrides NixOS aliases)
    update = "sudo pacman -Syu";
    install = "sudo pacman -S";
    remove = "sudo pacman -R";
    search = "pacman -Ss";

    # AUR helper (if yay is installed)
    yi = "yay -S";
    ys = "yay -Ss";

    # Omarchy management
    omarchy-update = "cd ~/.local/share/omarchy && git pull && ./install.sh";

    # Common aliases (merged from base)
    ls = "eza --icons";
    ll = "eza -la --icons";
    la = "eza -a --icons";
    lt = "eza --tree --icons";
    ".." = "cd ..";
    "..." = "cd ../..";

    # Git
    g = "git";
    ga = "git add";
    gc = "git commit";
    gst = "git status";

    # Kubernetes
    k = "kubectl";
    kctx = "kubectl config use-context";
    kns = "kubectl config set-context --current --namespace";

    # Docker
    d = "docker";
    dc = "docker-compose";
    dps = "docker ps";

    # Terraform
    tf = "terraform";

    # Modern CLI tools
    cat = "bat --paging=never";
    find = "fd";
    grep = "rg";

    # Linux utilities
    o = "xdg-open";
    open = "xdg-open";

    # Systemd
    sc = "systemctl";
    scu = "systemctl --user";
    jc = "journalctl";
    jcf = "journalctl -f";
  };

  # Hyprland-specific additions (complements Omarchy's config)
  home.file.".config/hypr/nix-me.conf".text = ''
    # nix-me additions to Hyprland config
    # Source this from your main hyprland.conf:
    # source = ~/.config/hypr/nix-me.conf

    # Additional keybindings
    bind = SUPER SHIFT, F, exec, fish  # Open fish shell
    bind = SUPER, K, exec, kubectl get pods  # Quick k8s status

    # Environment variables for Nix
    env = PATH,$HOME/.nix-profile/bin:$PATH
    env = NIX_PATH,nixpkgs=flake:nixpkgs

    # Fish shell integration
    exec-once = fish -c 'starship init fish | source'
  '';

  # Alacritty config additions (Omarchy uses Alacritty)
  home.file.".config/alacritty/nix-me.toml".text = ''
    # nix-me additions to Alacritty config
    # Import this in your main alacritty.toml:
    # import = ["~/.config/alacritty/nix-me.toml"]

    [shell]
    program = "${pkgs.fish}/bin/fish"

    [font]
    size = 14.0

    [font.normal]
    family = "JetBrainsMono Nerd Font"
    style = "Regular"
  '';

  # Environment variables
  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    BROWSER = "chromium";
    # Ensure Nix binaries are in PATH
    PATH = "$HOME/.nix-profile/bin:$PATH";
  };

  # Allow home-manager to manage itself
  programs.home-manager.enable = true;
}
