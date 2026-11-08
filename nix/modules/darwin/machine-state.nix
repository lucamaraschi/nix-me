{ config, inputs, lib, pkgs, hostname, machineType, username, ... }:

let
  root = inputs.self.outPath;
  layer = scope: name: source: path: {
    id = "${scope}:${name}";
    inherit scope name source path;
    state = config.nixMe.machineStateOverrides."${scope}:${name}" or
      (if builtins.pathExists (root + "/${path}") then builtins.fromJSON (builtins.readFile (root + "/${path}")) else { });
  };
  profiles = lib.sort builtins.lessThan (lib.unique config.apps.state.settingsProfiles);
  layers = [ (layer "shared" "all" "nix/hosts/types/shared/default.nix" "config/machine-state/shared.json") ]
    ++ lib.optional (machineType != null) (layer "type" machineType "nix/hosts/types/${machineType}/default.nix" "config/machine-state/types/${machineType}.json")
    ++ map (name: layer "profile" name "nix/hosts/profiles/${name}.nix" "config/machine-state/profiles/${name}.json") profiles
    ++ [ (layer "machine" hostname "nix/hosts/machines/${hostname}/default.nix" "config/machine-state/machines/${hostname}.json") ];
  merged = lib.foldl' (acc: item: lib.recursiveUpdate acc item.state) { } layers;
  # Profiles are peers, not an alphabetical priority list. Require an explicit
  # machine choice when two profiles disagree about the same package.
  profileChoices = kind: lib.foldl' (acc: item:
    lib.foldlAttrs (choices: name: enabled: choices // {
      ${name} = lib.unique ((choices.${name} or [ ]) ++ [ enabled ]);
    }) acc (item.state.software.${kind} or { })
  ) { } (lib.filter (item: item.scope == "profile") layers);
  machine = (lib.last layers).state;
  conflicts = kind: lib.attrNames (lib.filterAttrs (name: values:
    builtins.length values > 1 && !(builtins.hasAttr name (machine.software.${kind} or { }))
  ) (profileChoices kind));
  state = config.nixMe.machineState;
  software = state.software or { };
  files = state.files or { };
  selection = kind: software.${kind} or { };
  additions = kind: lib.attrNames (lib.filterAttrs (_: enabled: enabled) (selection kind));
  filterEntries = kind: entries:
    lib.filter (entry: (selection kind).${entry.name} or true) entries;
  safePath = path:
    path != "" && !(lib.hasPrefix "/" path)
    && lib.all (part: part != ".." && part != "." && part != "") (lib.splitString "/" path);
in {
  options.nixMe.machineState = lib.mkOption {
    type = lib.types.attrs;
    internal = true;
    default = merged;
    description = "Reviewed shared, type, profile, and machine overrides; not a secret store.";
  };
  options.nixMe.machineStateOverrides = lib.mkOption {
    type = lib.types.attrs;
    internal = true;
    default = { };
    description = "In-memory layer replacements used for read-only save previews.";
  };
  options.nixMe.driftDestinations = lib.mkOption {
    type = lib.types.listOf lib.types.attrs;
    internal = true;
    readOnly = true;
    default = layers;
  };
  # Filter the resolved lists, including entries contributed directly by profiles.
  options.homebrew.brews = lib.mkOption { apply = filterEntries "formula"; };
  options.homebrew.casks = lib.mkOption { apply = filterEntries "cask"; };
  # Keep capability reporting in this module so reviewed upgrades also work on older checkouts.
  options.nixMe.manifest = lib.mkOption {
    apply = manifest: manifest // {
      reconciliationVersion = 1;
      reconciliationScopesVersion = 1;
      managedFiles = lib.mapAttrsToList (name: file: {
        inherit name;
        inherit (file) target executable recursive;
        source = toString file.source;
      }) (lib.filterAttrs (_: file: file.enable) config.home-manager.users.${username}.home.file);
    };
  };

  config = {
    assertions = [
      { assertion = (state.schemaVersion or 1) == 1 && lib.all (item: (item.state.schemaVersion or 1) == 1) layers; message = "Unsupported machine-state schema version"; }
      { assertion = conflicts "formula" == [ ] && conflicts "cask" == [ ]; message = "Saved software choices conflict between profiles. Choose an explicit machine override."; }
      { assertion = lib.all (item: item.scope == "machine" || (item.state.files or { }) == { }) layers; message = "Saved dotfiles must stay in machine-specific state."; }
      { assertion = lib.all safePath (lib.mapAttrsToList (name: file: file.target or name) files); message = "Machine-state files must be relative home paths without traversal"; }
    ];
    # Match the priority of the central cask defaults, without replacing profile declarations.
    homebrew.casks = lib.mkDefault (additions "cask");
    homebrew.brews = additions "formula";
    home-manager.users.${username}.home.file = lib.mapAttrs (name: file:
      if !(file.enable or true) then { enable = lib.mkForce false; }
      else {
        enable = lib.mkForce true;
        target = lib.mkForce (file.target or name);
        text = lib.mkForce null;
        source = lib.mkForce (pkgs.writeText "nix-me-kept-file" file.text);
        executable = lib.mkForce (file.executable or false);
      }
    ) files;
  };
}
