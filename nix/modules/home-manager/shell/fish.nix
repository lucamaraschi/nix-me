# modules/home-manager/shell/fish.nix
# macOS-specific Fish shell configuration
# Imports shared base and adds Darwin-specific settings
{ config, lib, pkgs, ... }:

{
  imports = [
    ../../shared/fish-base.nix
  ];

  # macOS-specific shell initialization (appended to base)
  programs.fish.interactiveShellInit = lib.mkAfter ''
    # macOS: Add Homebrew to PATH
    fish_add_path /opt/homebrew/bin
    fish_add_path /opt/homebrew/sbin

    # Claude Code shell integration (macOS app path)
    if test -d "/Applications/Claude Code.app/Contents/Resources/app/bin"
      fish_add_path "/Applications/Claude Code.app/Contents/Resources/app/bin"
    end

    # macOS-specific trash function
    function trash
      command trash $argv
    end
  '';

  # macOS-specific aliases (merged with base)
  programs.fish.shellAliases = {
    # Darwin system management
    update = "darwin-rebuild switch --flake ~/.config/nixpkgs";
    upgrade = "nix flake update ~/.config/nixpkgs && darwin-rebuild switch --flake ~/.config/nixpkgs";
    rebuild = "darwin-rebuild switch --flake ~/.config/nixpkgs";

    # macOS utilities
    o = "open";
    oa = "open -a";
    finder = "open -a Finder";

    # Flush DNS cache
    flushdns = "sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder";

    # Show/hide hidden files in Finder
    showfiles = "defaults write com.apple.finder AppleShowAllFiles YES && killall Finder";
    hidefiles = "defaults write com.apple.finder AppleShowAllFiles NO && killall Finder";

    # Lock screen
    lock = "pmset displaysleepnow";
  };
}
