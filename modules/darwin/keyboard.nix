{ ... }:

{
  # Keyboard configuration
  system.keyboard = {
    enableKeyMapping = true;
    remapCapsLockToControl = true;
  };
  
  # Touch ID for sudo
  security.pam.services.sudo_local.touchIdAuth = true;
}