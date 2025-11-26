# hosts/macbook/display.nix
{ config, lib, pkgs, ... }:

{
  # MacBook-specific display configuration
  system.activationScripts.macbookDisplay.text = lib.mkAfter ''
    # Set built-in display to "More Space" scaling
    if [[ -n "$(system_profiler SPDisplaysDataType | grep "Built-in")" ]]; then
      defaults write com.apple.systempreferences.plist com.apple.preference.displays AppleDisplayScaleFactor -int 2
    fi
  '';
}