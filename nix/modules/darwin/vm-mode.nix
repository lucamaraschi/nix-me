# modules/darwin/vm-mode.nix
# Module for VM testing - skips features that don't work in VMs
{ lib, ... }:

{
  # Disposable VMs should not require a separate Homebrew bootstrap before
  # their first nix-darwin activation.
  homebrew.enable = lib.mkForce false;

  # Mac App Store authentication is unavailable in disposable VMs.
  homebrew.masApps = lib.mkForce { };

  # Additional VM-specific settings can be added here
  # For example:
  # - Reduced timeout for operations
  # - Skip certain services that don't work in VMs
  # - Disable features that require specific hardware
}
