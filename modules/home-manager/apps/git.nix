{ config, lib, pkgs, ... }:

{
  programs.git = {
    enable = true;
    userName = "Luca Maraschi";
    userEmail = "luca.maraschi@gmail.com";
    lfs.enable = true;
    
    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = false;
      core.editor = "vim";
      push.autoSetupRemote = true;
    };
    
    aliases = {
      co = "checkout";
      ci = "commit";
      st = "status";
      br = "branch";
      amend = "commit --amend";
      unstage = "reset HEAD --";
      last = "log -1 HEAD";
      sync-branches = "!git fetch --prune && git branch -vv | grep ': gone]' | awk '{print $1}' | xargs git branch -D";
    };
    
    ignores = [
      ".DS_Store"
      "*.swp"
      ".direnv"
      "node_modules"
    ];
  };
}