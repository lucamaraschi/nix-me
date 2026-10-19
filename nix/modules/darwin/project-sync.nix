{ config, hostname, lib, pkgs, username, ... }:

let
  cfg = config.projects;
  projectType = lib.types.submodule {
    options = {
      name = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        visible = false;
        description = "Resolved project name, derived from the projects.repos attribute name.";
      };

      url = lib.mkOption {
        type = lib.types.str;
        description = "Git clone URL.";
      };

      path = lib.mkOption {
        type = lib.types.str;
        description = "Project path, relative to the user's home unless absolute.";
      };

      branch = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optional branch to clone and fast-forward.";
      };

      remote = lib.mkOption {
        type = lib.types.str;
        default = "origin";
        description = "Remote name to fetch and pull from.";
      };

      clone = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to clone the project if it is missing.";
      };

      update = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to fetch and fast-forward the project when present.";
      };
    };
  };

  readProjectFile = path:
    if builtins.pathExists path then
      let
        parsed = builtins.fromJSON (builtins.readFile path);
      in
      if builtins.isAttrs parsed then parsed
      else throw "${toString path} must contain a JSON object"
    else
      { };

  sharedProjects = readProjectFile (cfg.settingsRoot + "/shared.json");
  profileProjects = map
    (profile: readProjectFile (cfg.settingsRoot + "/profiles/${profile}.json"))
    (lib.sort builtins.lessThan (lib.unique cfg.settingsProfiles));
  machineProjects = readProjectFile (cfg.settingsRoot + "/machines/${hostname}.json");

  mergedProjects =
    lib.foldl'
      lib.recursiveUpdate
      { }
      (cfg.sets ++ [ sharedProjects ] ++ profileProjects ++ [ machineProjects cfg.repos ]);

  finalRepos =
    lib.mapAttrsToList
      (name: repo: repo // { inherit name; })
      mergedProjects;

  projectPaths = map (repo: repo.path) finalRepos;

  projectSyncScript = pkgs.writeShellApplication {
    name = "sync-projects";
    runtimeInputs = with pkgs; [
      coreutils
      git
      jq
    ];
    text = builtins.readFile ../../../tools/installation/sync-projects.sh;
  };
  userHome = "/Users/${username}";
in
{
  options.projects = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to manage developer projects declaratively.";
    };

    syncOnActivation = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to clone and update configured projects during activation.";
    };

    sets = lib.mkOption {
      type = lib.types.listOf (lib.types.attrsOf projectType);
      default = [ ];
      description = "Reusable imported project sets.";
    };

    settingsRoot = lib.mkOption {
      type = lib.types.path;
      default = ../../../config/projects;
      description = "User-owned shared, profile, and machine project declarations.";
    };

    settingsProfiles = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Active profile project scopes, merged after shared projects and before machine projects.";
    };

    repos = lib.mkOption {
      type = lib.types.attrsOf projectType;
      default = { };
      description = "Additional or overriding projects for the current profile or host.";
    };

    finalRepos = lib.mkOption {
      type = lib.types.listOf projectType;
      readOnly = true;
      default = finalRepos;
      description = "Resolved projects after imported sets and local additions are merged.";
    };
  };

  config = lib.mkIf config.projects.enable {
    assertions = [
      {
        assertion = lib.length projectPaths == lib.length (lib.unique projectPaths);
        message = "projects.repos entries must not share the same target path.";
      }
    ];

    system.activationScripts.postActivation.text = lib.mkIf config.projects.syncOnActivation (lib.mkAfter ''
      echo "Syncing configured projects..." >&2
      if ! sudo -u ${username} HOME=${userHome} USER=${username} \
        ${projectSyncScript}/bin/sync-projects \
        --home ${userHome} \
        --projects-json ${lib.escapeShellArg (builtins.toJSON finalRepos)}; then
        echo "Warning: one or more projects need attention. Run 'make sync-projects' for details." >&2
      fi
    '');
  };
}
