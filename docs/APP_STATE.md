# Declarative application state

The app-state layer manages application preferences without symlinking files that
macOS or an application expects to own. It is opt-in, so existing configurations
retain their current activation behavior.

Enable it in a host or profile module:

```nix
apps.state.enable = true;
```

The setup wizard can write this flag. A successful `darwin-rebuild switch` then
runs the engine after system activation with missing applications and manual
checklist work skipped. Failures are reported without invalidating the Nix system
generation; rerun `nix-me apps diff` for the detailed plan.

Recipes describe mechanics and values describe policy:

```sh
nix-me apps diff \
  --recipe packages/app-state/recipes/rectangle.yaml \
  --values packages/app-state/values/rectangle.yaml

nix-me apps apply \
  --recipe packages/app-state/recipes/rectangle.yaml \
  --values packages/app-state/values/rectangle.yaml --yes
```

Multiple `--values` arguments are merged in order with later files winning by
deep merge. Use `--json` for the stable version-1 plan, `--only` to restrict app
IDs, and `--no-exec` to audit discovery, mutation, delivery, and poke commands
without executing them. State and file checksums live under
`~/.local/state/nix-me/apps.json`.

Before planning any writes, the engine aggregates recipe preflight failures.
On macOS it checks Accessibility, Input Monitoring, and Screen Recording through
their non-prompting system APIs, and checks readable sandbox container roots for
Full Disk Access. A missing grant stops the whole plan with the exact System
Settings pane; the engine never requests a grant midway through apply.

Rectangle is the migration example: `nix/modules/home-manager/rectangle.nix` keeps
its legacy defaults activation while app state is disabled, but steps aside when
`apps.state.enable` is true. Installation remains in the existing package layer;
`packages/app-state/recipes/rectangle.yaml` and `packages/app-state/values/rectangle.yaml` then own configuration.

Recipes without a CI-produced `verified` stamp warn by default. Use
`--require-verified` in stricter environments. Real application UI verification
and one-click imports remain macOS harness or human checks; the headless engine
does not claim those outcomes.

Local recipe maintainers can run the same validation and configurability
aggregation used by CI:

```sh
nix-me-apps registry validate --recipe recipes --json
nix-me-apps registry catalog-validate \
  --catalog packages/app-state/catalog/homebrew-top-200-apps.json --recipe recipes --json
nix-me-apps registry catalog-metric \
  --catalog packages/app-state/catalog/homebrew-top-200-apps.json --recipe recipes --json
nix-me-apps registry codec-smoke --json
```

The checked-in [zero-click metric](../packages/app-state/metrics/zero-click.json) is regenerated in
CI and fails validation when it becomes stale. See [Local catalog operations](REGISTRY.md)
for VM verification and trust-boundary details. Continued T3 verification,
recipe expansion, capture UX, and compatibility work is tracked separately in
the [configuration harness plan](HARNESS_PLAN.md).
