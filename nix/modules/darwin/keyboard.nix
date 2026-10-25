{ lib, ... }:

{
  # Keyboard configuration
  system.keyboard = {
    enableKeyMapping = lib.mkDefault true;
    remapCapsLockToControl = lib.mkDefault true;
  };
}
