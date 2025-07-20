{ config, pkgs, inputs, ... }:

{
  # Import your existing home-manager modules with Linux adaptations
  imports = [
    ../../modules/home-manager/git.nix       # Your Git config
    ../../modules/home-manager/tmux.nix      # Your tmux config
    ../../modules/home-manager/direnv.nix    # Your direnv config
    # Add other modules as needed
  ];

  home.username = "dev";
  home.homeDirectory = "/home/dev";
  home.stateVersion = "23.11";

  # Ghostty with Linux keybindings (adapt your existing config)
  programs.ghostty = {
    enable = true;
    # Copy settings from modules/home-manager/ghostty.nix but with Linux keys
    keybindings = {
      "ctrl+shift+c" = "copy_to_clipboard";
      "ctrl+shift+v" = "paste_from_clipboard";
      "ctrl+shift+t" = "new_tab";
    };
  };

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