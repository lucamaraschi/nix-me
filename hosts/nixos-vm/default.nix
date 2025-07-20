{ config, lib, pkgs, inputs, ... }:

{
  # Import your existing shared configuration
  imports = [
    ../shared/default.nix  # Reuse your shared configs
  ];

  system.stateVersion = "23.11";
  
  # Boot configuration
  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
    kernelPackages = pkgs.linuxPackages_latest;
  };

  # Basic system setup
  networking = {
    hostName = "nixos-vm";
    networkmanager.enable = true;
    firewall.allowedTCPPorts = [ 22 ];
  };

  time.timeZone = "America/Vancouver";
  i18n.defaultLocale = "en_US.UTF-8";

  # Desktop environment
  services.xserver = {
    enable = true;
    displayManager.lightdm.enable = true;
    windowManager.i3.enable = true;
    windowManager.i3.extraPackages = with pkgs; [
      rofi i3status i3lock picom feh
    ];
  };

  # Audio
  sound.enable = true;
  hardware.pulseaudio.enable = true;

  # VM user
  users.users.dev = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
    shell = pkgs.zsh;
    initialPassword = "dev";
  };

  # Essential packages
  environment.systemPackages = with pkgs; [
    git curl wget htop tree
    spice-vdagent open-vm-tools
  ];

  # Services
  services = {
    openssh.enable = true;
    spice-vdagentd.enable = true;
  };

  # VM optimizations
  virtualisation = {
    vmware.guest.enable = true;
    spiceUSBRedirection.enable = true;
  };

  security.sudo.wheelNeedsPassword = false;
  programs.zsh.enable = true;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
}