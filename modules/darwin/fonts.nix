{ pkgs, ... }:

{
  # Font configuration
  fonts = {
    # Enable font directory
    fontDir.enable = true;
    
    # Install these fonts
    packages = with pkgs; [
      (nerdfonts.override { fonts = [ "FiraCode" "JetBrainsMono" ]; })
      font-awesome
      material-design-icons
      tenderness
      spleen
      inter
      sf-mono
      source-code-pro
    ];
  };
}