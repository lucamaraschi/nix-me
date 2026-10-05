{ config, lib, pkgs, ... }:

{
  programs.git = {
    enable = true;
    lfs.enable = true;
    userName = "Luca Maraschi";
    userEmail = "luca.maraschi@gmail.com";
    signing.format = "openpgp";

    ignores = [
      ".DS_Store"
      "*.swp"
      ".direnv"
      "node_modules"
    ];

    aliases = {
      co = "checkout";
      ci = "commit";
      st = "status";
      br = "branch";
      amend = "commit --amend";
      unstage = "reset HEAD --";
      last = "log -1 HEAD";
      sync-branches = "!git fetch --prune && git branch -vv | grep ': gone]' | awk '{print $1}' | xargs git branch -D";
      sync = "!git fetch --all --prune && git branch -vv | grep ': gone]' | awk '{print $1}' | xargs git branch -d";
    };

    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = false;
      core.editor = "vim";
      push.autoSetupRemote = true;
    };
  };
}
