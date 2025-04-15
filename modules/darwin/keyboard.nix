{ ... }:

{
  # Keyboard configuration
  system.keyboard = {
    enableKeyMapping = true;
    remapCapsLockToControl = true;
  };
  
  # Touch ID for sudo
  security.pam.enableSudoTouchIdAuth = true;
}