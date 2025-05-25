# hosts/vm/default.nix
{ pkgs, config, lib, ... }:

{
  # Disable problematic activation scripts for VMs
  system.activationScripts.extraActivation.text = lib.mkForce "";
  
  # VM-specific settings
  system.defaults = {
    # Simplified dock settings for VMs
    dock = {
      autohide = true;
      tilesize = 36;
      static-only = true;
    };
    
    # Simplified finder settings for VMs
    finder = {
      CreateDesktop = false; # Hide desktop icons in VMs
    };
  };
  
  # VM-specific optimizations
  homebrew.casks = [
    # Minimal set of applications for VMs
    "visual-studio-code"
    "google-chrome"
  ];
  
  # Disable energy management scripts for VMs
  system.activationScripts.postActivation.text = lib.mkForce ''
    # Touch a last-rebuild file so we can tell when the system was last rebuilt
    printf "%s" "$(date)" > "$HOME"/.nix-last-rebuild
  '';
}