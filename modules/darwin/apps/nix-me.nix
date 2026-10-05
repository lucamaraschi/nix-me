{ config, pkgs, lib, username, inputs, ... }:

let
  # Create nix-me CLI wrapper
  nix-me-cli = pkgs.writeScriptBin "nix-me" ''
    #!${pkgs.bash}/bin/bash
    SCRIPT_DIR="${config.users.users.${username}.home}/.config/nixpkgs"

    if [ ! -f "$SCRIPT_DIR/bin/nix-me" ]; then
      echo "Error: nix-me not found at $SCRIPT_DIR/bin/nix-me"
      echo "Please ensure your nix-me configuration is properly installed"
      exit 1
    fi

    exec "$SCRIPT_DIR/bin/nix-me" "$@"
  '';
in
{
  options.apps.state = {
    enable = lib.mkEnableOption "declarative macOS application state";
    recipes = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ../../../recipes ];
      description = "Recipe files or directories passed to nix-me-apps.";
    };
    values = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ../../../values/rectangle.yaml ];
      description = "Ordered application value files; later files win by deep merge.";
    };
  };

  config = {
    # Add nix-me and its app-state engine to system packages.
    environment.systemPackages = [ nix-me-cli inputs.self.packages.${pkgs.system}.nix-me-apps ];

    system.activationScripts.postActivation.text = lib.mkIf config.apps.state.enable (lib.mkAfter ''
      echo "Converging declarative application state..." >&2
      set +e
      sudo -u ${lib.escapeShellArg username} env HOME=${lib.escapeShellArg config.users.users.${username}.home} \
        ${inputs.self.packages.${pkgs.system}.nix-me-apps}/bin/nix-me-apps apply \
        ${lib.concatMapStringsSep " " (path: "--recipe ${lib.escapeShellArg (toString path)}") config.apps.state.recipes} \
        ${lib.concatMapStringsSep " " (path: "--values ${lib.escapeShellArg (toString path)}") config.apps.state.values} \
        --yes --skip-manual --skip-missing
      apps_status=$?
      set -e
      if [ "$apps_status" -ne 0 ] && [ "$apps_status" -ne 3 ]; then
        echo "warning: app-state convergence exited $apps_status; run 'nix-me apps diff' for details" >&2
      fi
    '');
  };
}
