# vm-fix.nix
{ lib, ... }:

{
  # Disable problematic activation scripts for VMs
  system.activationScripts.extraActivation.text = lib.mkForce "";
  
  # Disable other potential conflicts
  system.activationScripts.postActivation.text = lib.mkForce ''
    # Minimal activation
    printf "%s" "$(date)" > "$HOME"/.nix-last-rebuild
  '';
}