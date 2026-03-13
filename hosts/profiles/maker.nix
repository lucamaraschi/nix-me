# Maker profile
# 3D printing, CAD, and fabrication tools
{ config, pkgs, lib, ... }:

{
  apps = {
    useBaseLists = true;

    # Maker GUI applications
    casksToAdd = [
      # 3D Printing
      "bambu-studio"        # Bambu Lab slicer
      "bambu-connect"       # Bambu Lab companion app

      # CAD & 3D Modeling
      "autodesk-fusion"     # Fusion 360
      "openscad"            # Programmatic CAD
      "blender"             # 3D modeling & rendering
      "freecad"             # Open source parametric CAD
    ];

    # Maker packages via Nix
    systemPackagesToAdd = [
      # meshlab removed - broken in nixpkgs (patch fails on 2025.07)
      # Install via: brew install --cask meshlab
    ];
  };
}
