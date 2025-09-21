{ config, pkgs, inputs, username, ... }:

{
  # Import your existing home-manager modules that work on Linux
  imports = [
    ../../modules/home-manager/apps/git.nix
    ../../modules/home-manager/apps/tmux.nix
    ../../modules/home-manager/shell/direnv.nix
    # Add other modules that are cross-platform
  ];

  home.username = "dev";
  home.homeDirectory = "/home/dev";
  home.stateVersion = "23.11";

  # Basic packages
  home.packages = with pkgs; [
    firefox
    ghostty  # Install ghostty as a package
  ];

  # Ghostty config file (not as a program)
  home.file.".config/ghostty/config".text = ''
    font-family = "JetBrains Mono"
    font-size = 14
    theme = "Catppuccin Mocha"
    
    # Linux keybindings
    keybind = ctrl+shift+c=copy_to_clipboard
    keybind = ctrl+shift+v=paste_from_clipboard
    keybind = ctrl+shift+t=new_tab
    keybind = ctrl+shift+w=close_surface
  '';

  # i3 window manager
  xsession.windowManager.i3 = {
    enable = true;
    config = {
      modifier = "Mod4";
      terminal = "ghostty";
      
      keybindings = let mod = "Mod4"; in {
        "${mod}+Return" = "exec ghostty";
        "${mod}+d" = "exec rofi -show drun";
        "${mod}+Shift+q" = "kill";
        "${mod}+f" = "fullscreen toggle";
        
        # Navigation
        "${mod}+j" = "focus left";
        "${mod}+k" = "focus down";
        "${mod}+l" = "focus up";
        "${mod}+semicolon" = "focus right";
        
        # Workspaces
        "${mod}+1" = "workspace number 1";
        "${mod}+2" = "workspace number 2";
        "${mod}+3" = "workspace number 3";
        "${mod}+4" = "workspace number 4";
        "${mod}+5" = "workspace number 5";
      };
    };
  };

  # Linux-specific environment
  home.sessionVariables = {
    EDITOR = "nvim";
    BROWSER = "firefox";
  };

  programs.home-manager.enable = true;
}