# modules/home-manager/ghostty.nix
{ config, lib, pkgs, ... }:

{
  # Ghostty terminal configuration
  home.file.".config/ghostty/config".text = ''
    # Ghostty Configuration

    # Font settings
    font-family = JetBrainsMono Nerd Font
    font-size = 13
    font-feature = calt
    font-feature = liga
    font-feature = ss01
    line-height = 1.2

    # UI settings
    window-decoration = false
    window-padding-x = 10
    window-padding-y = 10
    
    # Color scheme - Tokyo Night
    background = #1a1b26
    foreground = #c0caf5
    selection-background = #364a82
    selection-foreground = #c0caf5
    cursor-color = #c0caf5
    
    # Tokyo Night colors
    palette = 0=#1a1b26
    palette = 1=#f7768e
    palette = 2=#9ece6a
    palette = 3=#e0af68
    palette = 4=#7aa2f7
    palette = 5=#bb9af7
    palette = 6=#7dcfff
    palette = 7=#a9b1d6
    palette = 8=#414868
    palette = 9=#f7768e
    palette = 10=#9ece6a
    palette = 11=#e0af68
    palette = 12=#7aa2f7
    palette = 13=#bb9af7
    palette = 14=#7dcfff
    palette = 15=#c0caf5
    
    # Shell integration
    shell-integration = true
    shell-integration-features = no-cursor,prompt-detection
    
    # Performance settings
    adjust-cell-width = -1
    adjust-cell-height = -1
    
    # Keybindings
    keybind = super+c=copy
    keybind = super+v=paste
    keybind = super+n=new_window
    keybind = super+shift+n=new_instance
    keybind = super+t=new_tab
    keybind = super+w=close_surface
    keybind = super+shift+w=confirm_quit
    keybind = super+equal=increase_font_size
    keybind = super+minus=decrease_font_size
    keybind = super+0=reset_font_size
    
    # Tab navigation
    keybind = super+shift+]>next_tab
    keybind = super+shift+[=previous_tab
    keybind = super+1=goto_tab:0
    keybind = super+2=goto_tab:1
    keybind = super+3=goto_tab:2
    keybind = super+4=goto_tab:3
    keybind = super+5=goto_tab:4
    keybind = super+6=goto_tab:5
    keybind = super+7=goto_tab:6
    keybind = super+8=goto_tab:7
    keybind = super+9=goto_tab:8
    
    # Cursor settings
    cursor-style = beam
    cursor-thickness = 2
    cursor-blink = true
    cursor-blink-interval = 750
    
    # Scrollback
    scrollback = 10000
    
    # Set fish as default shell
    command = ${pkgs.fish}/bin/fish
  '';
}