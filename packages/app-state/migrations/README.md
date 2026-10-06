# App-state migration fixtures

These fixtures establish migration mechanics before any production version-2
format exists. `fixtures/manifest.json` declares forward and backward cases for
recipes, plans, and persisted state, including each source version, target
version, input, and expected canonical output.

Version 2 in this directory is deliberately synthetic. It changes only the
document version and adds `_nix_me_migration_fixture` with
`production_supported: false`. Ordinary recipe and state loaders continue to
reject it. A future production v2 must define a separate transition rather than
reusing or weakening this marker.

Run a non-mutating inspection from `packages/app-state/engine`:

```sh
cargo run -p nix-me-apps -- migrate \
  --kind state --input ../migrations/fixtures/state/v1.json \
  --from 1 --to 2 --dry-run --json
```

Apply requires a separate explicit flag:

```sh
cargo run -p nix-me-apps -- migrate \
  --kind state --input /path/to/apps.json \
  --from 1 --to 2 --apply --json
```

Apply validates both shapes first, then creates a same-directory `0600` backup,
writes and fsyncs a temporary file, and atomically renames it over the input. Any
failure after backup creation triggers an atomic restore from that backup. The
success or failure report names the backup and rollback paths. Unknown raw-tree
fields are preserved when the production v1 decoder can safely validate the
document; invalid or reserved paths fail before mutation with their reason.
