# Configuration Harness Plan

This document tracks the declarative application-state harness independently
from the repository-wide monorepo plan. Update it whenever the engine contract,
recipe catalog, verification authority, or rollout policy changes.

Last updated: 2026-10-04

## Current release boundary

Version 0.1 provides an opt-in, runtime-free `nix-me-apps` engine. It can:

- validate version-1 recipes and merged profile values;
- plan and apply typed defaults, files, command-managed sets, generated import
  artifacts, and manual residue;
- capture preference changes and inspect or watch exported artifacts;
- preserve unowned state, serialize concurrent apply operations, and recover
  safely from a corrupt state file;
- audit commands without executing them;
- measure local recipe coverage against the mapped Homebrew top-200 catalog;
- run through `nix-me apps` and optional nix-darwin post-activation convergence.

The persisted state format and JSON plan surface are version 1. Unknown future
versions must be rejected rather than interpreted as version 1. Recipes remain
local to this repository and are treated as untrusted until schema and semantic
validation pass.

## Verification tiers

- [x] T0: schema, semantic, registry, metric, and codec validation.
- [x] T1: headless convergence, drift, idempotence, failure, and corruption tests.
- [x] T2: disposable macOS preference-domain parity test.
- [ ] T3: visible application behavior and generated-import acceptance.

Only T3 evidence may replace a recipe's `verified: null` value. A verification
stamp records the macOS version, application version, date, and harness revision.

## Iteration backlog

### 1. Complete T3 verification

Priority: next

- Verify Rectangle preference changes in a disposable macOS VM.
- Verify Raycast accepts a generated import and reflects its settings.
- Record reproducible evidence and stamp only the recipes actually observed.
- Keep failed VMs and emitted plans as diagnostic artifacts.

Complete when the T3 procedure is repeatable by someone other than the recipe
author and CI cannot accept a hand-authored verification stamp.

### 2. Expand high-value recipe coverage

Priority: ongoing

- Select candidates from `packages/app-state/catalog/homebrew-top-200-apps.json` by rank,
  configurability, and confidence.
- Capture or research the real persistence mechanism before writing a recipe.
- Add recipe, values, catalog override, tests, and regenerated metric together.
- Prefer zero-click convergence; represent unavoidable interaction honestly as
  `one_click` or `full_manual` residue.

Initial candidates should prioritize installed applications shared by multiple
nix-me profiles rather than optimizing the percentage in isolation.

### 3. Improve capture ergonomics

Priority: after T3

- Add a guided application/domain discovery flow.
- Produce reviewable diffs before writing recipe or values fragments.
- Explain omitted secret-like values and require explicit inclusion.
- Add fixtures for every newly supported container or encryption pipeline.

### 4. Expose app-state status to clients

Priority: after the management API package boundary is established

- Add a versioned management API response for engine availability, configured
  recipes, drift counts, manual residue, and last apply status.
- Keep mutation behind explicit action endpoints; snapshot reads stay read-only.
- Make the macOS app consume the API contract rather than engine files or state
  files directly.

### 5. Harden upgrades and recovery

Priority: before changing either version-1 format

- Reject unsupported recipe, plan, and persisted-state versions explicitly.
- Define fixture-backed migrations before introducing a version 2.
- Add backup and rollback behavior for state migrations.
- Document compatibility between CLI, engine, recipes, and management clients.

## Development commands

```sh
cd packages/app-state/engine
cargo fmt --all -- --check
cargo test --workspace
cargo run -p nix-me-apps -- registry validate --recipe ../recipes --json
cargo run -p nix-me-apps -- registry catalog-validate \
  --catalog ../catalog/homebrew-top-200-apps.json --recipe ../recipes --json
cargo run -p nix-me-apps -- registry catalog-metric \
  --catalog ../catalog/homebrew-top-200-apps.json --recipe ../recipes --json
```

The manual VM command and trust model are documented in `docs/REGISTRY.md`.

## Decision log

- 2026-10-04: Keep the harness in the nix-me monorepo because recipes, Nix
  activation, the CLI, and management clients share one versioned contract.
- 2026-10-04: Merge the tested v0.1 engine with recipes unverified rather than
  claiming visible application behavior that has not passed T3.
- 2026-10-04: Track harness iteration here instead of expanding the repository
  migration plan with engine-specific implementation details.
