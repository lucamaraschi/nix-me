{ pkgs, ... }:

{
  # Font configuration
  fonts = {
    
    # Install these fonts
    packages = with pkgs; [
      nerdfonts.firaCode
      nerdfonts.jetbrainsMono
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