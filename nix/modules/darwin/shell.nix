{ pkgs, lib, ... }:

{
  # Shell environment configuration
  environment = {
        
    # List of allowed shells
    shells = lib.mkDefault (with pkgs; [ 
      bash 
      zsh 
      fish 
    ]);
    
    # Shell aliases available for all users
    shellAliases = lib.mkDefault {
      l = "ls -la";
      update = "darwin-rebuild switch --flake ~/.config/nixpkgs";
    };
  };
  
  # Ensure Fish is properly setup
  system.activationScripts.postActivation.text = ''
    # Add Fish to /etc/shells if it's not already there
    if [ -f /etc/shells ]; then
      grep -q '${pkgs.fish}/bin/fish' /etc/shells || echo '${pkgs.fish}/bin/fish' | sudo tee -a /etc/shells
    else
      echo '${pkgs.fish}/bin/fish' | sudo tee /etc/shells
    fi
  '';
  
  # Programs configuration
  programs = {
    # Enable Fish shell
    fish.enable = lib.mkDefault true;
    
    # GNU tools with their original names
    gnupg.agent.enable = lib.mkDefault true;
  };
}