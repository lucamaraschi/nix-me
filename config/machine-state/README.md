# Reviewed machine changes

Nix Me saves explicitly reviewed local changes to the selected destination:

- `shared.json`: every Darwin host in this configuration.
- `types/<type>.json`: hosts with this exact machine type (not descendant types).
- `profiles/<profile>.json`: hosts that enable that settings profile.
- `machines/<hostname>.json`: this host only, the default.

These overlays are imported by nix-darwin; the original Nix modules are not
rewritten. Host membership comes from evaluated Nix configuration. New hosts
using the same type/profile inherit its saved choices too. Profile membership
uses `apps.state.settingsProfiles`, which the supplied profile modules declare.

`software.formula` and `software.cask` map package names to booleans: true
includes a package; false excludes it from the final Homebrew list.
`files` maps a Home Manager declaration name to
`{ "target": "relative/home/path", "text": "...", "executable": false }`,
or `{ "target": "relative/home/path", "enable": false }` to stop managing a deleted file. File overrides take
precedence over profile declarations. Remove an override to inherit again.

Review file contents before keeping them here: these files are plain text,
not a secret store. Nix will also put managed contents into its store.
Credentials and private application data do not belong here.

Homebrew selections are declarative; Homebrew versions are not pinned.
Software choices merge from shared, to exact machine type, to profiles, to
machine. Profiles are peers: conflicting package choices require an explicit
machine override rather than arbitrary alphabetical precedence. The preview
evaluates every affected host and explains preserved host exceptions. It does
not apply any machine or stage, commit, or push Git.

Each app or tool has its own destination dropdown and expandable details.
Items going to different destinations can be reviewed and saved together;
validation or write failures roll back the batch without overwriting concurrent
edits. Dotfiles remain machine-only, even alongside shared software changes.
Changing any item's destination invalidates the previous save approval.
