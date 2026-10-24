{ config, pkgs, lib, username, hostname, inputs, ... }:

let
  # Create nix-me CLI wrapper
  nix-me-cli = pkgs.writeScriptBin "nix-me" ''
    #!${pkgs.bash}/bin/bash
    SCRIPT_DIR="${config.users.users.${username}.home}/.config/nixpkgs"

    if [ ! -f "$SCRIPT_DIR/apps/cli/bin/nix-me" ]; then
      echo "Error: nix-me not found at $SCRIPT_DIR/apps/cli/bin/nix-me"
      echo "Please ensure your nix-me configuration is properly installed"
      exit 1
    fi

    exec "$SCRIPT_DIR/apps/cli/bin/nix-me" "$@"
  '';

  cfg = config.apps.state;
  filesIn = directory:
    if builtins.pathExists directory then
      let
        entries = builtins.readDir directory;
        names = lib.sort builtins.lessThan (builtins.attrNames entries);
      in
      map (name: directory + "/${name}") (lib.filter
        (name:
          entries.${name} == "regular" &&
          (lib.hasSuffix ".json" name || lib.hasSuffix ".yaml" name || lib.hasSuffix ".yml" name))
        names)
    else
      [ ];
  sharedValues = filesIn (cfg.settingsRoot + "/shared");
  profileValues = lib.concatMap
    (profile: filesIn (cfg.settingsRoot + "/profiles/${profile}"))
    (lib.sort builtins.lessThan (lib.unique cfg.settingsProfiles));
  machineValues = filesIn (cfg.settingsRoot + "/machines/${hostname}");
  machineEnableFile = cfg.settingsRoot + "/machines/${hostname}/enabled";
  machineEnableDefault =
    if builtins.pathExists machineEnableFile then
      let
        parsed = builtins.tryEval (builtins.fromJSON (builtins.readFile machineEnableFile));
      in
      if parsed.success && builtins.isBool parsed.value then
        parsed.value
      else
        throw "${toString machineEnableFile} must contain a JSON boolean"
    else
      false;
  resolvedValues = cfg.values ++ sharedValues ++ profileValues ++ machineValues;
in
{
  options.apps.state = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = machineEnableDefault;
      description = "Whether declarative macOS application state is enabled for this host.";
    };
    recipes = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ../../../../packages/app-state/recipes ];
      description = "Recipe files or directories passed to nix-me-apps.";
    };
    values = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ../../../../packages/app-state/values/rectangle.yaml ];
      description = "Ordered application value files; later files win by deep merge.";
    };
    settingsRoot = lib.mkOption {
      type = lib.types.path;
      default = ../../../../config/app-state;
      description = "User-owned shared, profile, and machine application settings.";
    };
    settingsProfiles = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Active profile setting scopes, merged after shared settings and before machine settings.";
    };
    resolvedValues = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      readOnly = true;
      description = "Complete ordered application values list after resolving setting scopes.";
    };
  };

  options.apps.manager.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Whether to install the locally built Nix Me macOS app in /Applications.";
  };

  config = {
    apps.state.enable = lib.mkIf machineEnableDefault (lib.mkForce true);
    apps.state.resolvedValues = resolvedValues;

    # The native app is referenced by the activation script below so nix-darwin
    # does not also expose a duplicate under /Applications/Nix Apps.
    environment.systemPackages = [
      nix-me-cli
      inputs.self.packages.${pkgs.system}.nix-me-tui
      inputs.self.packages.${pkgs.system}.nix-me-apps
    ];

    system.activationScripts.postActivation.text = lib.mkAfter ''
      ${lib.optionalString config.apps.manager.enable ''
        manager_source=${lib.escapeShellArg "${inputs.self.packages.${pkgs.system}.nix-me-macos}/Applications/Nix Me.app"}
        manager_dir="/Applications"
        manager_target="$manager_dir/Nix Me.app"
        manager_stage="$manager_dir/.Nix Me.app.nix-me-new"
        manager_state_dir="/var/db/nix-me"
        manager_receipt="$manager_state_dir/manager-app"
        legacy_target=${lib.escapeShellArg "${config.users.users.${username}.home}/Applications/Nix Me.app"}

        mkdir -p "$manager_dir" "$manager_state_dir"
        rm -rf "$manager_stage"
        echo "Installing Nix Me in $manager_target..." >&2
        /usr/bin/ditto "$manager_source" "$manager_stage"
        chown -R root:wheel "$manager_stage"

        if [ -e "$manager_target" ] || [ -L "$manager_target" ]; then
          rm -rf "$manager_target"
        fi
        mv "$manager_stage" "$manager_target"
        printf '%s\n' "$manager_source" > "$manager_receipt"
        chmod 0644 "$manager_receipt"

        if [ -L "$legacy_target" ]; then
          rm "$legacy_target"
        fi

        launch_services="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
        if [ -x "$launch_services" ]; then
          "$launch_services" -f "$manager_target" >/dev/null 2>&1 || true
        fi
      ''}

      ${lib.optionalString (!config.apps.manager.enable) ''
        manager_target="/Applications/Nix Me.app"
        manager_receipt="/var/db/nix-me/manager-app"
        if [ -f "$manager_receipt" ]; then
          echo "Removing Nix-managed $manager_target..." >&2
          rm -rf "$manager_target"
          rm "$manager_receipt"
        fi
      ''}

      ${lib.optionalString config.apps.state.enable ''
        echo "Converging declarative application state..." >&2
        set +e
        sudo -u ${lib.escapeShellArg username} env HOME=${lib.escapeShellArg config.users.users.${username}.home} \
          ${inputs.self.packages.${pkgs.system}.nix-me-apps}/bin/nix-me-apps apply \
          ${lib.concatMapStringsSep " " (path: "--recipe ${lib.escapeShellArg (toString path)}") config.apps.state.recipes} \
          ${lib.concatMapStringsSep " " (path: "--values ${lib.escapeShellArg (toString path)}") config.apps.state.resolvedValues} \
          --yes --skip-manual --skip-missing
        apps_status=$?
        set -e
        if [ "$apps_status" -ne 0 ] && [ "$apps_status" -ne 3 ]; then
          echo "warning: app-state convergence exited $apps_status; run 'nix-me apps diff' for details" >&2
        fi
      ''}
    '';
  };
}
