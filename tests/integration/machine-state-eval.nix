let
  flake = builtins.getFlake (toString ../..);
  system = flake.darwinConfigurations.nabucodonosor.extendModules {
    modules = [
      ({ lib, ... }: {
        nixMe.machineState = {
          schemaVersion = 1;
          software = {
            formula = { git = false; "test-kept-formula" = true; };
            cask = { "direct-test-cask" = false; "test-kept-cask" = true; };
          };
          files = {
            ".config/ghostty/config" = { text = "font-size = 16\n"; executable = false; };
            ".claude/CLAUDE.md" = { enable = false; };
          };
        };
        homebrew.casks = lib.mkDefault [ "direct-test-cask" ];
      })
    ];
  };
  cfg = system.config;
  manifest = cfg.nixMe.manifest;
  files = cfg.home-manager.users.batman.home.file;
  scopeState = software: { schemaVersion = 1; inherit software; };
  scoped = host: overrides: (flake.darwinConfigurations.${host}.extendModules {
    modules = [{ nixMe.machineStateOverrides = overrides; }];
  }).config;
  choices = {
    "shared:all" = scopeState { formula.shared-tool = true; };
    "type:macbook" = scopeState { formula.shared-tool = false; formula.laptop-tool = true; };
    "profile:dev" = scopeState { formula.profile-tool = true; cask.profile-app = true; };
    "machine:nabucodonosor" = scopeState { cask.profile-app = false; };
  };
  host = scoped "nabucodonosor" choices;
  peer = scoped "zion" choices;
  unrelated = scoped "gotham" choices;
  names = c: map (item: item.name) c.homebrew.brews;
  casks = c: map (item: item.name) c.homebrew.casks;
  conflicting = scoped "nabucodonosor" {
    "profile:dev" = scopeState { formula.peer-conflict = true; };
    "profile:work" = scopeState { formula.peer-conflict = false; };
  };
in
assert !(builtins.elem "git" manifest.software.homebrew.formulae);
assert builtins.elem "test-kept-formula" manifest.software.homebrew.formulae;
assert !(builtins.elem "direct-test-cask" manifest.software.homebrew.casks);
assert builtins.elem "test-kept-cask" manifest.software.homebrew.casks;
assert files.".config/ghostty/config".text == null;
assert files.".config/ghostty/config".executable == false;
assert !(files ? ".claude/CLAUDE.md") || !files.".claude/CLAUDE.md".enable;
assert manifest.reconciliationVersion == 1;
assert manifest.reconciliationScopesVersion == 1;
assert !(builtins.elem "shared-tool" (names host));
assert builtins.elem "shared-tool" (names peer);
assert builtins.elem "laptop-tool" (names host);
assert builtins.elem "profile-tool" (names peer);
assert !(builtins.elem "profile-tool" (names unrelated));
assert !(builtins.elem "profile-app" (casks host));
assert builtins.elem "profile-app" (casks peer);
assert builtins.any (a: !a.assertion && a.message == "Saved software choices conflict between profiles. Choose an explicit machine override.") conflicting.assertions;
{
  passed = true;
  scopedDestinations = builtins.length host.nixMe.driftDestinations;
  filesTracked = builtins.length manifest.managedFiles;
}
