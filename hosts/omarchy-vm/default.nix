# hosts/omarchy-vm/default.nix
# NixOS configuration for Omarchy-style development VM
# A development-focused Linux VM with Fish shell, modern CLI tools, and full GUI
{ config, pkgs, lib, ... }:

let
  sharedPackages = import ../../modules/shared/packages.nix { inherit pkgs; };
in
{
  imports = [
    ./hardware-configuration.nix
  ];

  # System configuration
  system.stateVersion = "23.11";
  nixpkgs.config.allowUnfree = true;

  # Boot configuration
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Networking
  networking = {
    hostName = "omarchy-vm";
    networkmanager.enable = true;
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 80 443 3000 8080 ];
    };
  };

  # Time zone and locale
  time.timeZone = "Europe/London";
  i18n.defaultLocale = "en_US.UTF-8";

  # Desktop Environment - GNOME for Omarchy-style experience
  services.xserver = {
    enable = true;

    # Keyboard
    xkb = {
      layout = "us";
      options = "ctrl:nocaps";  # Caps Lock as Ctrl
    };
  };

  # Display manager and desktop (new location in NixOS 24.05+)
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  # Audio
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Enable SSH
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = true;
      PermitRootLogin = "no";
    };
  };

  # Docker
  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
  };

  # Users
  users.users.dev = {
    isNormalUser = true;
    description = "Developer";
    extraGroups = [ "wheel" "networkmanager" "docker" "audio" "video" ];
    initialPassword = "dev";
    shell = pkgs.fish;
  };

  # Enable Fish shell system-wide
  programs.fish.enable = true;

  # System packages
  environment.systemPackages = with pkgs;
    sharedPackages.commonPackages
    ++ sharedPackages.vmDevPackages
    ++ [
      # GNOME extras
      gnome-tweaks
      gnome-terminal
      dconf-editor

      # Development
      git
      gitui
      lazygit

      # Editors
      neovim
      vim

      # Terminal emulators
      ghostty
      alacritty

      # Browsers
      firefox
      chromium

      # File manager
      nautilus
      gnome-disk-utility

      # Virtualization tools
      qemu
      virt-manager

      # System monitoring
      gnome-system-monitor

      # Screenshot and recording
      gnome-screenshot

      # Archive management
      file-roller

      # Text editor (GUI)
      gnome-text-editor
    ];

  # GNOME settings - Omarchy-style
  services.gnome = {
    core-apps.enable = true;
    gnome-keyring.enable = true;
  };

  # Auto-login for convenience in VM
  services.displayManager.autoLogin = {
    enable = true;
    user = "dev";
  };

  # Workaround for GNOME auto-login
  systemd.services."getty@tty1".enable = false;
  systemd.services."autovt@tty1".enable = false;

  # Environment variables
  environment.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    BROWSER = "firefox";
  };

  # Fonts
  fonts.packages = with pkgs; [
    nerd-fonts.fira-code
    nerd-fonts.jetbrains-mono
    nerd-fonts.hack
    font-awesome
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-emoji
  ];

  # Enable Flatpak for additional apps
  services.flatpak.enable = true;

  # Garbage collection
  nix = {
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };
    settings = {
      auto-optimise-store = true;
      experimental-features = [ "nix-command" "flakes" ];
    };
  };
}
