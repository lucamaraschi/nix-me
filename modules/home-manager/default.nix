{ config, lib, pkgs, username, ... }:

{
  imports = [
    ./apps           # User app configurations
    ./shell          # Shell and environment configurations
  ];
  
  # Home Manager basics
  home.stateVersion = "23.11";
  home.homeDirectory = lib.mkForce "/Users/${username}";
  
  # Generic environment variables
  home.sessionVariables = {
    EDITOR = "vim";
    VISUAL = "code";
    LANG = "en_US.UTF-8";
    LC_ALL = "en_US.UTF-8";
  };
}