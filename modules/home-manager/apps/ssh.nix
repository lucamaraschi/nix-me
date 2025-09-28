{ config, lib, pkgs, ... }:

{
  programs.ssh = {
    enable = true;

    matchBlocks = {
      "github.com" = {
        hostname = "github.com";
        extraOptions = {
          AddKeysToAgent = "yes";
          IdentitiesOnly = "no";  # Critical: allows 1Password agent keys
        };
      };

      "*" = {
        extraOptions = {
          AddKeysToAgent = "yes";
          ServerAliveInterval = "60";
          ServerAliveCountMax = "30";
          TCPKeepAlive = "yes";
          StrictHostKeyChecking = "accept-new";
          ForwardAgent = "no";
        };
      };
    };

    extraConfig = ''
      # 1Password SSH agent configuration
      IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"

      # Include additional SSH configs if they exist
      Include ~/.ssh/config.local
    '';
  };

  home.packages = with pkgs; [
    gh  # GitHub CLI with 1Password authentication support
  ];
}
