{ config, lib, pkgs, ... }:

{
  programs.git = {
    enable = true;
    userName = "Your Name";
    userEmail = "your.email@example.com";
    
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
    };
    
    ignores = [
      ".DS_Store"
      "*.swp"
      ".direnv"
      "node_modules"
    ];
  };
}