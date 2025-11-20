# modules/nixos/fish.nix
# NixOS/Linux-specific Fish shell configuration
# Imports shared base and adds Linux-specific settings
{ config, lib, pkgs, ... }:

{
  imports = [
    ../shared/fish-base.nix
  ];

  # Linux-specific shell initialization (appended to base)
  programs.fish.interactiveShellInit = lib.mkAfter ''
    # Linux: Add common binary paths
    fish_add_path /usr/local/bin
    fish_add_path ~/.local/share/flatpak/exports/bin
    fish_add_path /var/lib/flatpak/exports/bin

    # Linux-specific trash function (uses trash-cli)
    function trash
      command trash-put $argv
    end

    # XDG environment
    set -gx XDG_CONFIG_HOME "$HOME/.config"
    set -gx XDG_DATA_HOME "$HOME/.local/share"
    set -gx XDG_CACHE_HOME "$HOME/.cache"
    set -gx XDG_STATE_HOME "$HOME/.local/state"
  '';

  # Linux-specific aliases (merged with base)
  programs.fish.shellAliases = {
    # NixOS system management
    update = "sudo nixos-rebuild switch --flake ~/.config/nixpkgs";
    upgrade = "nix flake update ~/.config/nixpkgs && sudo nixos-rebuild switch --flake ~/.config/nixpkgs";
    rebuild = "sudo nixos-rebuild switch --flake ~/.config/nixpkgs";
    rebuild-boot = "sudo nixos-rebuild boot --flake ~/.config/nixpkgs";
    rebuild-test = "sudo nixos-rebuild test --flake ~/.config/nixpkgs";

    # Linux utilities
    o = "xdg-open";
    open = "xdg-open";

    # Systemd
    sc = "systemctl";
    scu = "systemctl --user";
    jc = "journalctl";
    jcf = "journalctl -f";

    # Linux system info
    ports = "ss -tulanp";
    mem = "free -h";
    disk = "df -h";

    # Package management (NixOS)
    nixgc = "nix-collect-garbage -d";
    nixopt = "nix-store --optimise";

    # Flatpak (if available)
    fp = "flatpak";
    fpup = "flatpak update";
    fps = "flatpak search";
    fpi = "flatpak install";
  };
}
