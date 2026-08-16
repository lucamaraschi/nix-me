{ config, inputs, lib, hostname, machineName, machineType, username, ... }:

let
  sourceRevision =
    if inputs.self ? rev then inputs.self.rev
    else if inputs.self ? dirtyRev then inputs.self.dirtyRev
    else "unknown";

  caskNames = lib.unique (map (cask: cask.name) config.homebrew.casks);
  formulaNames = lib.unique (map (formula: formula.name) config.homebrew.brews);
  nixPackageNames = lib.unique (map (package: package.name or (lib.getName package)) config.environment.systemPackages);

  licenseName = license:
    if license == null then null
    else if builtins.isList license then
      lib.concatStringsSep ", " (lib.filter (name: name != null) (map licenseName license))
    else if builtins.isAttrs license then license.spdxId or license.shortName or license.fullName or null
    else toString license;

  homepageValue = homepage:
    if homepage == null then null
    else if builtins.isList homepage then lib.concatStringsSep ", " homepage
    else toString homepage;

  nixPackageDetails = map (package:
    let
      metadata = package.meta or { };
      packageVersion = package.version or (lib.getVersion package);
    in {
      name = package.pname or (lib.getName package);
      fullName = package.name or (lib.getName package);
      version = if packageVersion == "" then null else packageVersion;
      description = metadata.description or null;
      homepage = homepageValue (metadata.homepage or null);
      license = licenseName (metadata.license or null);
    }
  ) config.environment.systemPackages;

  manifest = {
    schemaVersion = 1;
    host = {
      inherit hostname machineName machineType username;
    };
    source = {
      revision = sourceRevision;
      dirty = !(inputs.self ? rev);
      contentHash = builtins.baseNameOf (toString inputs.self.outPath);
      lockHash = builtins.hashFile "sha256" ../../flake.lock;
    };
    software = {
      nixPackages = nixPackageNames;
      inherit nixPackageDetails;
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
