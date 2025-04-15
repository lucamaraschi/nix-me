{ config, lib, pkgs, ... }:

{
  imports = [
    ./fish.nix
    ./git.nix
  ];
  
  # Home Manager basics
  home.stateVersion = "23.11";
  
  # Install user packages
  home.packages = with pkgs; [
    ripgrep
    fd
    jq
    htop
    fzf
    tree
    bat
  ];
  
  # Generic environment variables
  home.sessionVariables = {
    EDITOR = "vim";
    VISUAL = "code";
    LANG = "en_US.UTF-8";
    LC_ALL = "en_US.UTF-8";
  };
}