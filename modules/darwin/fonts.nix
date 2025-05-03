{ pkgs, ... }:

{
  # Font configuration
  fonts = {
    
    # Install these fonts
    packages = with pkgs; [
      nerd-fonts.firaCode
      nerd-fonts.jetbrainsMono
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