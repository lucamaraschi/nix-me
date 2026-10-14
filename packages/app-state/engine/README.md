# nix-me app-state engine

`nix-me-apps` converges application preferences, files, CLI-managed sets, manual
checklists, and generated import artifacts from registry recipes and profile values.
It never symlinks application state.

## Development

```sh
cargo test --workspace
cargo run -p nix-me-apps -- diff \
  --recipe ../recipes/rectangle.yaml \
  --values ../values/rectangle.yaml --json
cargo run -p nix-me-apps -- registry validate --recipe ../recipes --json
cargo run -p nix-me-apps -- registry catalog-validate \
  --catalog ../catalog/homebrew-top-200-apps.json --recipe ../recipes --json
cargo run -p nix-me-apps -- registry catalog-metric \
  --catalog ../catalog/homebrew-top-200-apps.json --recipe ../recipes --json
cargo run -p nix-me-apps -- registry codec-smoke --json
```

Version migration is never implicit in `status`, `diff`, or `apply`. Inspect a
migration with `migrate --dry-run`, then opt into mutation with `migrate --apply`:

```sh
cargo run -p nix-me-apps -- migrate \
  --kind state --input ../migrations/fixtures/state/v1.json \
  --from 1 --to 2 --dry-run --json
```

The checked-in forward/backward fixture matrix and the atomic backup/rollback
contract are documented in [`../migrations/README.md`](../migrations/README.md).
The only implemented v2 shape is explicitly synthetic and remains unsupported
by ordinary production loaders.

To turn an app export into reviewable state, inspect it once or watch the
scheduled-backup file continuously:

```sh
cargo run -p nix-me-apps -- capture --sniff backup.rayconfig --json
cargo run -p nix-me-apps -- capture --sniff backup.rayconfig --watch \
  --output profile/raycast-import.json --commit --json
```

On macOS the default preference backend calls CoreFoundation's CFPreferences API.
The `defaults(1)` backend is retained as a buildable fallback and the convergence
core is tested on every platform using `FakePrefStore` and replay command runners.

The real-app checks are intentionally split from headless tests:

- T0/T1: `cargo test --workspace` (required before merge).
- T2: `tests/macos_real.rs`, using scratch domains only (run on a Mac runner).
- T3: Rectangle and Raycast visible/import confirmation checks (VM/human harness).

The stable CLI surface is exposed through `nix-me apps diff|apply|capture`.
AES pipeline primitives are implemented in-process; the installed binary does not
shell out to OpenSSL or require a language runtime.
