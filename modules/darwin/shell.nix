{ pkgs, ... }:

{
  # Shell environment configuration
  environment = {
        
    # List of allowed shells
    shells = with pkgs; [ 
      bash 
      zsh 
      fish 
    ];
    
    # Shell aliases available for all users
    shellAliases = {
      l = "ls -la";
      update = "darwin-rebuild switch --flake ~/.config/nixpkgs";
    };
  };
  
  # Ensure Fish is properly setup
  system.activationScripts.postActivation.text = ''
    # Add Fish to /etc/shells if it's not already there
    grep -q '${pkgs.fish}/bin/fish' /etc/shells || echo '${pkgs.fish}/bin/fish' | sudo tee -a /etc/shells
  '';
  
  # Programs configuration
  programs = {
    # Enable Fish shell
    fish.enable = true;
    
    # GNU tools with their original names
    gnupg.agent.enable = true;
  };
}