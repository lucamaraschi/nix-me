# modules/darwin/display.nix
{ config, lib, pkgs, ... }:

{
  
  # Install required packages
  environment.systemPackages = with pkgs; [
    # Ensure these tools are available
    coreutils
    gnugrep
    gnused
    curl
  ];
}