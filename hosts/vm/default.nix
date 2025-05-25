{ pkgs, config, lib, ... }:

{
  # VM-specific settings - minimal and optimized for virtual environments
  
  # VM-specific system defaults
  system.defaults = {
    # Simplified dock settings for VMs
    dock = {
      autohide = true;
      tilesize = 36;
      static-only = true;
      show-recents = false;
    };
    
    # Simplified finder settings for VMs
    finder = {
      CreateDesktop = false; # Hide desktop icons in VMs
      AppleShowAllExtensions = true;
      FXEnableExtensionChangeWarning = false;
    };
    
    # Minimal global domain preferences for VMs
    NSGlobalDomain = {
      AppleInterfaceStyle = "Dark";
      NSDocumentSaveNewDocumentsToCloud = false;
      NSAutomaticCapitalizationEnabled = false;
      NSAutomaticSpellingCorrectionEnabled = false;
    };
  };
  
  # VM-specific homebrew packages (minimal set)
  homebrew.casks = [
    # Essential development tools only
    "visual-studio-code"
    "google-chrome"
    "ghostty"
    
    # Basic productivity
    "rectangle"
  ];
  
  # Override problematic activation scripts for VMs
  system.activationScripts.vmOptimization.text = ''
    echo "Configuring VM optimizations..." >&2
    
    # Disable spotlight indexing for better VM performance
    sudo mdutil -a -i off 2>/dev/null || echo "Could not disable spotlight indexing"
    
    # Touch a last-rebuild file
    printf "%s" "$(date)" > "$HOME"/.nix-last-rebuild
  '';
  
  # Disable energy management for VMs (no battery management needed)
  # Override any energy-related activation scripts from other modules
}