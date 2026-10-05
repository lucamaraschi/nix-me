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

Run the contract tests from the repository root:

```sh
make test-api test-actions test-details
```
