# modules/darwin/apps/codex.nix
# Repair Codex Desktop when Homebrew has a cask receipt but the app artifact is missing.
{ config, lib, username, ... }:

let
  caskName = cask:
    if lib.isAttrs cask then cask.name or "" else cask;

  codexAppEnabled =
    config.homebrew.enable
    && lib.any (cask: caskName cask == "codex-app") config.homebrew.casks;

  brew = "${config.homebrew.brewPrefix}/brew";
  brewUser = lib.escapeShellArg config.homebrew.user;
in
{
  system.activationScripts.postActivation.text = lib.mkIf codexAppEnabled (lib.mkAfter ''
    echo "Checking Codex Desktop app..." >&2

    if [ -x "${brew}" ] \
      && sudo --user=${brewUser} --set-home "${brew}" list --cask codex-app >/dev/null 2>&1 \
      && [ ! -d "/Applications/Codex.app" ]; then
      echo "  Homebrew reports codex-app installed, but /Applications/Codex.app is missing." >&2
      echo "  Reinstalling codex-app cask..." >&2

      if sudo --user=${brewUser} --set-home env HOMEBREW_NO_AUTO_UPDATE=1 "${brew}" reinstall --cask codex-app; then
        if [ -d "/Applications/Codex.app" ]; then
          /usr/bin/mdimport /Applications/Codex.app 2>/dev/null || true
          /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
            -f /Applications/Codex.app 2>/dev/null || true
          echo "  Codex Desktop repaired." >&2
        fi
      else
        echo "  Warning: failed to reinstall codex-app. Run: brew reinstall --cask codex-app" >&2
      fi
    fi
  '');
}
