# Management API

This package is the versioned process boundary used by the native app, CLI,
and future clients. Commands emit JSON on stdout and diagnostics on stderr.

- `nix-me-api` provides read-only snapshots and focused views.
- `nix-me-action` validates and performs explicit mutations.
- `nix-me-details` resolves package metadata lazily.

Clients must invoke these executables rather than reading generated manifests,
Nix modules, or application-state files directly.

The current snapshot contract is version 1 and is recorded in
`schema/snapshot-v1.schema.json`. Additive fields may be introduced within a
version. Removing fields, changing their meaning, or changing their type
requires a new schema version and coordinated client fixtures.

`localAI` is an optional additive snapshot member for older-client
compatibility. New API responses always provide its version 1 read-only status,
and `nix-me-api local-ai` provides the focused view. Component states distinguish
known absence (`missing`, `notBuilt`, `stopped`, or `drifted`) from
`unavailable`; refresh is bounded and never builds DS4, downloads a model,
starts or stops a server, clones a checkout, applies harness state, or launches
an app.

Model download, cancellation, checksum, cleanup, and other lifecycle mutations
are intentionally not part of this status contract. They require a separate,
explicit action contract (LAI-005).

Run the contract tests from the repository root:

```sh
make test-api test-actions test-details
```
