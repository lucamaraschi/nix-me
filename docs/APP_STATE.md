# Declarative application state

The app-state layer manages application preferences without symlinking files that
macOS or an application expects to own. It is opt-in, so existing configurations
retain their current activation behavior.

Enable it for a host by importing the beta profile:

```nix
extraModules = [
  ./nix/hosts/profiles/beta.nix
];
```

The profile is never imported by default. A custom profile can enable the same
option directly when application-state management is part of that profile's
contract:

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

## User-owned settings

Reusable recipes and shipped baseline values remain under `packages/app-state`.
Settings captured from a user's Mac live separately under `config/app-state`:

```text
config/app-state/
  shared/settings.json
  profiles/<profile>/settings.json
  machines/<hostname>/enabled
  machines/<hostname>/settings.json
```

Nix merges shipped values, shared settings, active profiles in sorted order, and
finally the current machine. The native app lets the user choose one of these
scopes, previews the redacted current values, and updates the selected tracked
JSON file only after explicit confirmation. It never stages, commits, or pushes
the resulting repository change.

The Application state screen inventories user-installed applications from
`/Applications` and `~/Applications` and merges them with the integration
registry by bundle ID. Each application shows its integration contract, managed
paths, the built-in, shared, active-profile, and machine files currently
contributing values, and its harness export boundary. Exportable integrations
list every declared preference key, structured file, or command-managed list
that Review and Save can convert into harness JSON. Installed
applications without an integration remain visible, but Nix Me will not read or
write their settings until a reviewed recipe defines the safe state boundary.

Every Homebrew cask and Mac App Store application declared by a Darwin host must
map to at least one recipe. Recipes use one of three honest boundaries:

- Structured files, declared defaults, and command-managed lists are shown as
  exportable and can be reviewed before they are saved and converged.
- A recipe may explicitly classify a user-authored text file as reviewed source.
  The native app asks before reading the exact file, shows the complete preview,
  and requires a separate Save action. Other unstructured files remain closed.
- Credential, cloud, license, and opaque database state is represented as an
  explicit manual step and is never copied into the repository.

`make test-app-coverage` evaluates every `darwinConfiguration` and fails when a
configured cask or Mac App Store identifier has no recipe. The same check runs as
part of `make test-app-state`.

The extensionless per-machine `enabled` file contains a JSON boolean and is not
loaded as application values. The native app can set it to `true`, after which
the user applies the pending Nix configuration to activate convergence.

The tracked empty files are deliberate: Git-backed flakes ignore untracked files,
so a newly created value file would not participate in evaluation until manually
added to Git. New profiles and machines should add their empty `settings.json`
file as part of their configuration skeleton.

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
