{ config, lib, pkgs, inputs, ... }:

{
  # Don't import shared - it's Darwin-specific
  # imports = [
  #   ../shared/default.nix  # ← REMOVE THIS
  # ];

  system.stateVersion = "23.11";
  
  # Boot configuration
  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
    kernelPackages = pkgs.linuxPackages_latest;
  };

  # Rest of the configuration stays the same...
  networking = {
    hostName = "nixos-vm";
    networkmanager.enable = true;
    firewall.allowedTCPPorts = [ 22 ];
  };

  time.timeZone = "America/Vancouver";
  i18n.defaultLocale = "en_US.UTF-8";

  services.xserver = {
    enable = true;
    displayManager.lightdm.enable = true;
    windowManager.i3.enable = true;
    windowManager.i3.extraPackages = with pkgs; [
      rofi i3status i3lock picom feh
    ];
  };

  hardware.pulseaudio.enable = true;

  users.users.dev = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
    shell = pkgs.zsh;
    initialPassword = "dev";
  };

  environment.systemPackages = with pkgs; [
    git curl wget htop tree
    spice-vdagent open-vm-tools
  ];

  services = {
    openssh.enable = true;
    spice-vdagentd.enable = true;
  };

  virtualisation = {
    vmware.guest.enable = true;
    spiceUSBRedirection.enable = true;
  };

  security.sudo.wheelNeedsPassword = false;
  programs.zsh.enable = true;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
}