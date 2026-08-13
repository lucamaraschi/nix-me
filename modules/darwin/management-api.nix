{ config, inputs, lib, hostname, machineName, machineType, username, ... }:

let
  sourceRevision =
    if inputs.self ? rev then inputs.self.rev
    else if inputs.self ? dirtyRev then inputs.self.dirtyRev
    else "unknown";

  caskNames = lib.unique (map (cask: cask.name) config.homebrew.casks);
  formulaNames = lib.unique (map (formula: formula.name) config.homebrew.brews);
  nixPackageNames = lib.unique (map lib.getName config.environment.systemPackages);

  manifest = {
    schemaVersion = 1;
    host = {
      inherit hostname machineName machineType username;
    };
    source = {
      revision = sourceRevision;
      dirty = !(inputs.self ? rev);
    };
    software = {
      nixPackages = nixPackageNames;
      homebrew = {
        casks = caskNames;
        formulae = formulaNames;
        masApps = config.homebrew.masApps;
      };
    };
    projects = config.projects.finalRepos;
  };
in
{
  options.nixMe.manifest = lib.mkOption {
    type = lib.types.attrs;
    readOnly = true;
    default = manifest;
    description = "Machine-readable description of the desired nix-me configuration.";
  };

  config.environment.etc."nix-me/manifest.json".text = builtins.toJSON config.nixMe.manifest;
}
