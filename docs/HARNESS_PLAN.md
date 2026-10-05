# Configuration Harness Plan

This document is the delivery plan and backlog for the declarative
application-state harness. Keep it separate from the repository-wide monorepo
plan and update it whenever scope, priority, or verification status changes.

Last updated: 2026-10-05

## Product outcome

The harness should let a user understand and safely converge application state
without learning where every application stores its preferences. The CLI and
macOS app must answer four questions from one versioned management contract:

1. What state is managed?
2. What differs from the declared configuration?
3. What will change if I apply it?
4. Did the application visibly accept the change?

The engine owns planning, validation, convergence, and evidence. Clients own
presentation and explicit user actions; they must not parse engine state files
or implement application-specific behavior.

## Guardrails

- Snapshot and diff operations are read-only.
- Every mutation requires an explicit apply action.
- Unowned state is preserved unless a recipe declares otherwise.
- Secret-like values are redacted by default and never captured implicitly.
- Unknown recipe, plan, and persisted-state versions are rejected.
- A recipe is not marked verified until visible behavior passes T3.
- Large or mutable artifacts such as local model weights are referenced and
  inspected, not copied into Nix or harness state.

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

The persisted state format and JSON plan surface are version 1. Recipes remain
local to this repository and are treated as untrusted until schema and semantic
validation pass.

## Verification tiers

- [x] T0: schema, semantic, registry, metric, and codec validation.
- [x] T1: headless convergence, drift, idempotence, failure, and corruption tests.
- [x] T2: disposable macOS preference-domain parity test.
- [ ] T3: visible application behavior and generated-import acceptance.

Only T3 evidence may replace a recipe's `verified: null` value. A verification
record must contain the macOS version, application version, date, harness
revision, procedure version, result, and retained evidence references.

## Delivery roadmap

### Phase 1: Establish trust

Complete H-001 through H-004. The outcome is a repeatable T3 workflow that
cannot be satisfied with a hand-edited stamp.

### Phase 2: Publish one status contract

Complete H-010 through H-012. The management API becomes the sole integration
point for the CLI and macOS app, including availability, drift, residue, and
last-apply state.

### Phase 3: Make capture reviewable

Complete H-020 through H-022. Users can discover candidate state, review a
redacted diff, and generate recipe/value fragments without directly editing
engine data.

### Phase 4: Grow recipe coverage

Complete H-030 and H-031, then repeat the scored batch process. Coverage is
driven by installed use and confidence, not by percentage alone.

### Phase 5: Prepare versioned upgrades

Complete H-040 and H-041 before introducing any version-2 recipe, plan, or
persisted-state format.

## Prioritized backlog

| ID | Priority | Status | Depends on | Deliverable and acceptance criteria |
|---|---|---|---|---|
| H-001 | P0 | Ready | - | Define a machine-readable T3 evidence manifest and JSON Schema. Validation rejects missing environment, procedure, result, or artifact metadata. |
| H-002 | P0 | Ready | H-001 | Run Rectangle T3 in a disposable macOS VM. A second operator can follow the documented procedure and reproduce the visible window-management behavior. |
| H-003 | P0 | Ready | H-001 | Run Raycast generated-import T3. Evidence proves the import was accepted and the corresponding setting is visible in Raycast. |
| H-004 | P0 | Ready | H-001 | Add verification-stamp generation and CI validation. Stamps are derived from passing evidence and cannot be accepted when hand-authored or stale. |
| H-010 | P1 | Ready | H-004 | Define an internal status model covering engine availability, configured recipes, drift, manual residue, last apply, and verification. Unit tests cover every state. |
| H-011 | P1 | Ready | H-010 | Expose the status model through a versioned, read-only management API. Contract tests lock response shape and error semantics. |
| H-012 | P1 | Ready | H-011 | Render harness status, diffs, residue, and apply results in the macOS app and CLI without reading engine files directly. Mutations remain explicit. |
| H-020 | P1 | Ready | H-012 | Add guided application/domain discovery. Output names each source, confidence level, unsupported container, and next safe action. |
| H-021 | P1 | Ready | H-020 | Add a reviewable capture diff that separates additions, changes, deletions, ignored keys, and uncertain values before writing files. |
| H-022 | P1 | Ready | H-021 | Add default secret redaction and explicit inclusion controls. Fixtures cover tokens, credentials, encrypted containers, and false positives. |
| H-030 | P2 | Ready | H-012 | Score recipe candidates by installed-profile frequency, configurability, impact, implementation confidence, and T3 cost. Publish the ranked queue. |
| H-031 | P2 | Ready | H-030 | Deliver the first scored recipe batch with values, catalog mapping, tests, metrics, documentation, and either T3 evidence or `verified: null`. |
| H-040 | P2 | Ready | H-012 | Create forward/backward migration fixtures for recipes, plans, and persisted state before any version-2 implementation starts. |
| H-041 | P2 | Ready | H-040 | Add atomic backup, migration rollback, and failure reporting. Tests prove the prior state remains usable after an interrupted migration. |

## Local AI pilot

The local-AI profile is a pilot for external runtimes whose installation is
declarative but whose large data and runtime lifecycle remain user-controlled.
Nix owns Pi, project declarations, commands, and baseline settings. DS4 model
weights remain outside the Nix store and require an explicit download.

| ID | Priority | Status | Depends on | Deliverable and acceptance criteria |
|---|---|---|---|---|
| LAI-001 | P0 | Done | - | Add a composable `local-ai` profile that installs Pi and syncs the public DS4 and pi-ds4 repositories under `~/src/ai`. It is not assigned to an existing host implicitly. |
| LAI-002 | P0 | Done | LAI-001 | Provide `local-ai-doctor` and `local-ai-setup`. Setup builds DS4, links Pi, and downloads DeepSeek V4 Flash Q2 only with `--download-model`; doctor reports prerequisites, memory, disk, runtime, extension, and model state. |
| LAI-003 | P1 | Ready | H-020, LAI-002 | Model Pi/DS4 settings as a harness recipe. Capture excludes model binaries and secrets; plan/apply converges settings without disrupting a running server. |
| LAI-004 | P1 | Ready | H-011, LAI-003 | Add local-AI status to the management API and macOS app: checkout health, runtime build, model presence, server state, configuration drift, and actionable remediation. |
| LAI-005 | P2 | Ready | LAI-004 | Add explicit model lifecycle actions with progress, disk preflight, checksum/error reporting, cancellation, and cleanup of partial downloads. |

## Release gates

### Harness 0.2

- H-001 through H-004 are complete.
- Rectangle and Raycast retain reproducible T3 evidence.
- CI rejects invalid or stale verification records.

### Management integration beta

- H-010 through H-012 are complete.
- CLI and macOS app consume the same API fixtures.
- Read-only refresh cannot trigger an apply or application launch.

### Capture beta

- H-020 through H-022 are complete.
- No secret-like value is emitted without explicit confirmation.
- Generated fragments pass registry validation before they are offered for use.

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

- 2026-10-05: Use stable backlog IDs and release gates so engine, API, CLI, and
  macOS app work can reference the same deliverables.
- 2026-10-05: Treat local AI as an external-runtime pilot. Declare tools and
  settings, but keep model downloads explicit and model weights out of Nix.
- 2026-10-04: Keep the harness in the nix-me monorepo because recipes, Nix
  activation, the CLI, and management clients share one versioned contract.
- 2026-10-04: Merge the tested v0.1 engine with recipes unverified rather than
  claiming visible application behavior that has not passed T3.
- 2026-10-04: Track harness iteration here instead of expanding the repository
  migration plan with engine-specific implementation details.
