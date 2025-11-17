# modules/darwin/vm-mode.nix
# Module for VM testing - skips features that don't work in VMs
{ config, lib, pkgs, ... }:

{
  # Skip Mac App Store apps (iCloud doesn't work in VMs)
  homebrew.skipMasApps = true;

  # Additional VM-specific settings can be added here
  # For example:
  # - Reduced timeout for operations
  # - Skip certain services that don't work in VMs
  # - Disable features that require specific hardware
}
