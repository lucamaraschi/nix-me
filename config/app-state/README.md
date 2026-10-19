# Application settings

This directory contains user-owned settings captured by the native Nix Me app.
It is separate from `packages/app-state`, which owns reusable recipes and
shipped baseline values.

Settings are merged in this order, with later scopes overriding earlier ones:

1. shipped values from `packages/app-state/values`;
2. `shared/settings.json` for every machine;
3. `profiles/<profile>/settings.json` for active profiles, sorted by profile name;
4. `machines/<hostname>/settings.json` for one machine.

The native app updates these tracked JSON files atomically. JSON is also valid
YAML, so the app-state engine reads generated JSON and hand-maintained YAML
through the same values loader. Secret-looking keys and high-entropy values are
removed before a preview can be saved.

Each machine's extensionless `enabled` file contains a JSON boolean. The native
app changes it to `true` when the user enables the harness; the extension keeps
the marker separate from application value files.

Git remains outside the native app. Review, commit, and publish these files with
the normal repository workflow.
