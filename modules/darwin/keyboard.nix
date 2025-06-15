{ lib, ... }:

{
  # Keyboard configuration
  system.keyboard = {
    enableKeyMapping = lib.mkDefault true;
    remapCapsLockToControl = lib.mkDefault true;
  };
  
  # Touch ID for sudo
  security.pam.services.sudo_local.touchIdAuth = lib.mkDefault true;
}