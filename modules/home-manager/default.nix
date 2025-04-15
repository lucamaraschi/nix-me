{ config, lib, pkgs, username, ... }:

{
  imports = [
    ./direnv.nix
    ./fish.nix
    ./ghostty.nix
    ./git.nix
    ./rectangle.nix
    ./ssh.nix
    ./tmux.nix
    ./vscode.nix
  ];
  
  # Home Manager basics
  home.stateVersion = "23.11";
  home.homeDirectory = lib.mkForce "/Users/${username}";
  
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