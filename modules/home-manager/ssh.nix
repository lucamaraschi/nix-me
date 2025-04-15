{ config, lib, pkgs, ... }:

{
  programs.ssh = {
    enable = true;
    
    matchBlocks = {
      "github.com" = {
        hostname = "github.com";
        # Don't specify identityFile when using 1Password
        extraOptions = {
          AddKeysToAgent = "yes";
        };
      };
      
      "*" = {
        # Global settings for all hosts
        extraOptions = {
          AddKeysToAgent = "yes";
          IdentitiesOnly = "yes";
          ServerAliveInterval = "60";
          ServerAliveCountMax = "30";
          TCPKeepAlive = "yes";
          StrictHostKeyChecking = "accept-new";
        };
      };
      
      # Add your other common SSH hosts here
      # Example:
      # "myserver" = {
      #   hostname = "myserver.example.com";
      #   port = 2222;
      #   user = "admin";
      #   # No identityFile needed with 1Password
      # };
    };
    
    extraConfig = ''
      # Include additional SSH configs if they exist
      Include ~/.ssh/config.local
      
      # 1Password SSH agent configuration
      # This points to the 1Password SSH agent socket
      IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
    '';
  };
  
  # Make sure 1Password is installed for SSH key management
  # (Should already be in your homebrew casks, but including here for reference)
  home.packages = with pkgs; [
    # Tools that integrate with 1Password
    gh  # GitHub CLI with 1Password authentication support
  ];
}