{ config, lib, pkgs, username, ... }:

{
  imports = [
    ./apps           # User app configurations
    ./shell          # Shell and environment configurations
  ];
  
  # Home Manager basics
  home.stateVersion = "23.11";
  home.homeDirectory = lib.mkForce "/Users/${username}";
  
  # Install user packages (these could move to apps/ too if desired)
  home.packages = with pkgs; [
    ripgrep
    fd
    jq
    htop
    fzf
    tree
    bat
  ];
}