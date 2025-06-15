{ pkgs, lib, ... }:

{
  # Font configuration
  fonts = {
    
    # Install these fonts
    packages = lib.mkDefault (with pkgs; [
      
      nerd-fonts.fira-code
      nerd-fonts.jetbrains-mono

      font-awesome
      material-design-icons
      tenderness
      spleen
      inter
      source-code-pro
    ]);
  };
}