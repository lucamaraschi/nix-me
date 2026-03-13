# modules/darwin/core.nix
{ pkgs, config, lib, username, ... }:

{
  system.stateVersion = 6;
  nixpkgs.config.allowUnfree = true;

  # Explicitly configure the primary user
  users.users.${username} = {
    name = username;
    home = "/Users/${username}";
  };

  # Core system configuration
  nix = {
    package = pkgs.nix;

    # Disable nix-darwin's Nix management (using Determinate Systems installer)
    enable = false;

    # These settings won't work with Determinate, but kept for reference
    # optimise.automatic = lib.mkDefault false;
    # gc = lib.mkDefault {
    #   automatic = false;
    #   interval = {
    #     Hour = 3;
    #     Minute = 0;
    #   };
    #   options = "--delete-older-than 30d";
    # };

    # Nix settings - these might not work with Determinate
    # settings = {
    #   experimental-features = [ "nix-command" "flakes" ];
    #   warn-dirty = false;
    # };

    # Updated nixPath configuration
    nixPath = [
      "darwin-config=/etc/nix-darwin/configuration.nix"
      "darwin=$HOME/.nix-defexpr/channels/darwin"
      "nixpkgs=$HOME/.nix-defexpr/channels/nixpkgs"
      "$HOME/.nix-defexpr/channels"
    ];
  };

  # Package management is handled by modules/darwin/apps/installations.nix
  # Profiles can customize via systemPackagesToAdd/systemPackagesToRemove

  # Add Nix paths to /etc/paths.d so GUI apps (VS Code, etc.) can find Nix binaries
  environment.etc."paths.d/nix".text = ''
    /run/current-system/sw/bin
    /etc/profiles/per-user/${username}/bin
    /nix/var/nix/profiles/default/bin
  '';

  # Pre-activation: backup /etc files that nix-darwin wants to manage
  system.activationScripts.preActivation.text = ''
    # Backup existing /etc files if they exist and aren't already managed by nix-darwin
    for f in /etc/shells /etc/bashrc /etc/zshrc /etc/zshenv; do
      if [ -f "$f" ] && [ ! -L "$f" ]; then
        if ! grep -q "nix-darwin" "$f" 2>/dev/null; then
          echo "Backing up $f to $f.before-nix-darwin" >&2
          mv "$f" "$f.before-nix-darwin" 2>/dev/null || true
        fi
      fi
    done
  '';

  # System activation
  system.activationScripts.postActivation.text = ''
    # Reset LaunchPad (as the actual user, not root)
    echo "Resetting LaunchPad..." >&2
    if [ -n "$USER" ] && [ "$USER" != "root" ]; then
      # Run as the actual user
      sudo -u "$USER" find "$HOME/Library/Application Support/Dock" -name "*.db" -maxdepth 1 -delete 2>/dev/null || echo "LaunchPad database not found (normal on fresh install)" >&2
    else
      echo "Skipping LaunchPad reset (running as root)" >&2
    fi

    # Touch a last-rebuild file so we can tell when the system was last rebuilt
    printf "%s" "$(date)" > "$HOME"/.nix-last-rebuild

    # Ensure ~/.config/nixpkgs points to the source repo
    # This avoids having two separate clones that drift out of sync
    REPO_SOURCE="$HOME/src/lm/nix-me"
    NIXPKGS_LINK="$HOME/.config/nixpkgs"
    if [ -d "$REPO_SOURCE/.git" ]; then
      if [ -L "$NIXPKGS_LINK" ]; then
        echo "$HOME/.config/nixpkgs symlink already exists" >&2
      elif [ -d "$NIXPKGS_LINK" ]; then
        echo "Backing up $HOME/.config/nixpkgs to $HOME/.config/nixpkgs.backup" >&2
        mv "$NIXPKGS_LINK" "$NIXPKGS_LINK.backup"
        ln -s "$REPO_SOURCE" "$NIXPKGS_LINK"
        echo "Created symlink $HOME/.config/nixpkgs -> $HOME/src/lm/nix-me" >&2
      else
        mkdir -p "$(dirname "$NIXPKGS_LINK")"
        ln -s "$REPO_SOURCE" "$NIXPKGS_LINK"
        echo "Created symlink $HOME/.config/nixpkgs -> $HOME/src/lm/nix-me" >&2
      fi
    fi
  '';
}
