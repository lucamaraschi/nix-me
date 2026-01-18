{ pkgs, config, lib, ... }:

{
  # VM-specific settings - minimal and optimized for virtual environments
  
  # VM-specific system defaults
  system.defaults = {
    # Simplified dock settings for VMs
    dock = {
      tilesize = lib.mkForce 36;
    };
    
    # Simplified finder settings for VMs
    finder = {
      CreateDesktop = false;
    };
    
    # Remove problematic CustomUserPreferences for VMs
    CustomUserPreferences = lib.mkForce {};
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

    # Disable Gatekeeper for VM environment (allows unsigned apps)
    echo "Disabling Gatekeeper for VM..." >&2
    sudo spctl --master-disable 2>/dev/null || true
    sudo xattr -r -d com.apple.quarantine /Applications 2>/dev/null || true

    # Disable spotlight indexing for better VM performance
    sudo mdutil -a -i off 2>/dev/null || echo "Could not disable spotlight indexing"

    # Touch a last-rebuild file
    printf "%s" "$(date)" > "$HOME"/.nix-last-rebuild
  '';
  
  # Disable energy management for VMs (no battery management needed)
  # Override any energy-related activation scripts from other modules
}