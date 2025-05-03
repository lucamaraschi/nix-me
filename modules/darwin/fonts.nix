{ pkgs, ... }:

{
  # Font configuration
  fonts = {
    
    # Install these fonts
    packages = with pkgs; [
      nerd-fonts.fira-code
      nerd-fonts.jetbrains-mono
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