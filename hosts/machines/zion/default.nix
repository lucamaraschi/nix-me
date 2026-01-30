{ pkgs, config, lib, ... }:

{
  # Zion - Mac Mini maker/craft station
  # Named after the last human city in The Matrix trilogy

  imports = [
    # Import Mac Mini base configuration
    ../../types/macmini/default.nix
  ];

  # Swap Ctrl and Command keys (both left and right)
  # Useful for PC-style keyboard layout
  # HID key codes: Ctrl Left=0xE0, Ctrl Right=0xE4, Cmd Left=0xE3, Cmd Right=0xE7
  system.keyboard.userKeyMapping = [
    # Left Control -> Left Command
    { HIDKeyboardModifierMappingSrc = 30064771296; HIDKeyboardModifierMappingDst = 30064771299; }
    # Right Control -> Right Command
    { HIDKeyboardModifierMappingSrc = 30064771300; HIDKeyboardModifierMappingDst = 30064771303; }
    # Left Command -> Left Control
    { HIDKeyboardModifierMappingSrc = 30064771299; HIDKeyboardModifierMappingDst = 30064771296; }
    # Right Command -> Right Control
    { HIDKeyboardModifierMappingSrc = 30064771303; HIDKeyboardModifierMappingDst = 30064771300; }
  ];

  # Maker/craft specific applications
  apps = {
    useBaseLists = true;

    # 3D printing and design apps
    casksToAdd = [
      # Streaming/Recording
      "elgato-camera-hub"     # Elgato Prompter & camera controls

      # Manual installs required (not in Homebrew):
      # - Cricut Design Space: https://design.cricut.com/
      # - Blackmagic ATEM Software Control: https://www.blackmagicdesign.com/support/family/atem-live-production-switchers
    ];

    # Design-related CLI tools
    systemPackagesToAdd = [
    ];
  };

  # Environment for maker projects
  environment.variables = {
    MAKER_PROJECTS = "$HOME/Maker";
  };
}
