# Managed projects

The Nix Me app writes project declarations here instead of rewriting hand-authored
Nix modules. Files contain a JSON object keyed by project name.

- `shared.json` applies to every host.
- `profiles/<profile>.json` applies when that profile is active.
- `machines/<hostname>.json` applies only to that host.

Scopes merge in that order. Existing `nix/projects/*.nix` sets are the base and
explicit `projects.repos` declarations remain the highest-priority override.
