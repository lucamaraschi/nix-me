# modules/home-manager/apps/default.nix
{ lib, ... }:

{
  imports = [
    ./ghostty.nix
    ./vscode.nix
    ./git.nix
    ./tmux.nix
    ./ssh.nix
  ];
}