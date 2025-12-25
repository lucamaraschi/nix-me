# modules/home-manager/apps/default.nix
{ lib, ... }:

{
  imports = [
    ./ghostty.nix
    ./vscode.nix
    ./git.nix
    ./tmux.nix
    ./ssh.nix
    ./claude-code.nix # Claude Code global settings
    ../rectangle.nix  # Rectangle window manager config
  ];
}