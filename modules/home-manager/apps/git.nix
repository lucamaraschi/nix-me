{ config, lib, pkgs, ... }:

{
  programs.git = {
    enable = true;
    lfs.enable = true;

    ignores = [
      ".DS_Store"
      "*.swp"
      ".direnv"
      "node_modules"
    ];

    settings = {
      user = {
        name = "Luca Maraschi";
        email = "luca.maraschi@gmail.com";
      };

      init.defaultBranch = "main";
      pull.rebase = false;
      core.editor = "vim";
      push.autoSetupRemote = true;

      alias = {
        co = "checkout";
        ci = "commit";
        st = "status";
        br = "branch";
        amend = "commit --amend";
        unstage = "reset HEAD --";
        last = "log -1 HEAD";
        sync-branches = "!git fetch --prune && git branch -vv | grep ': gone]' | awk '{print $1}' | xargs git branch -D";
      };
    };
  };
}