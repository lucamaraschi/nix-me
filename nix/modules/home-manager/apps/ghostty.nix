# modules/home-manager/apps/ghostty.nix
{ config, lib, pkgs, ... }:

{
  # Ghostty terminal configuration
  home.file.".config/ghostty/config".text = ''
    # Ghostty Configuration

    # Font settings
    font-family = JetBrainsMono Nerd Font
    font-size = 13

    # UI settings
    window-decoration = false
    window-padding-x = 10
    window-padding-y = 10

    # Color scheme - Tokyo Night
    background = #1a1b26
    foreground = #c0caf5

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

    # Key bindings
    # Configure shift+enter for Claude Code compatibility
    keybind = shift+enter=text:\x1b[13;2u

    # Shell
    command = ${pkgs.fish}/bin/fish
  '';
}
