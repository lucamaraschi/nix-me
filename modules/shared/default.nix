# modules/shared/default.nix
# Platform-agnostic modules that work on both Darwin and Linux
{ lib, ... }:

{
  imports = [
    # Package lists are imported explicitly where needed
    # ./packages.nix  # Not a NixOS module, just a function
  ];
}
