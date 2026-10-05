# Nix Me Plan

This document is the source of truth for repository-wide work that spans more
than one application or package. Update the status and decision notes in the
same pull request as the related change.

Last updated: 2026-10-04

## Current status

- [x] Separate `feature/configuration-harness` from the macOS application
  history. The harness branch is based directly on `main`; the app commits
  remain on their own branch.
- [x] Merge the native macOS application independently. Pull request #17
  preserved the ten application commits and merged them into `main`.
- [x] Complete and merge the configuration harness independently in pull
  request #19. Continued harness iteration lives in `docs/HARNESS_PLAN.md`.
- [x] Refactor the repository into explicit monorepo boundaries.
- [x] Move code without changing behavior, then repair imports and tooling.
- [x] Add path-aware validation and application-specific release workflows.

## Architectural boundaries

- Keep `flake.nix`, `flake.lock`, and `Makefile` at the repository root as the
  workspace entry points.
- Treat the management API as a versioned contract. Applications consume its
  JSON output instead of importing Nix files or harness internals.
- Give every independently runnable application its own README, tests, build
  command, and release lifecycle.
- Keep shared packages free of application UI and distribution concerns.
- Avoid combining directory moves with feature or behavior changes.

## Target layout

```text
apps/
  cli/
  macos/
  post-install-tui/

packages/
  app-state/
    catalog/
    engine/
    metrics/
    recipes/
    values/
  management-api/

nix/
  hosts/
  modules/
  projects/
  overlays/

tools/
  development/
  installation/
  release/

tests/
  integration/
  vm/

docs/
flake.nix
flake.lock
Makefile
PLAN.md
```

The layout is a target, not a requirement to move every file. A move should
make ownership or dependency direction clearer; otherwise the file stays at
the root.

## Milestones

### 1. Merge the configuration harness

Status: complete

- Finish the harness on `feature/configuration-harness` without app changes.
- Define its inputs, outputs, persistence format, and compatibility policy.
- Add focused unit and integration tests.
- Document how the CLI and management API invoke it.
- Merge it through an independent pull request.

Complete when the harness is on `main`, its tests run in CI, and no macOS UI or
distribution changes are included in its pull request.

### 2. Establish monorepo boundaries

Status: complete

- Create a dedicated repository-layout branch from the then-current `main`.
- Record ownership and dependency direction before moving files.
- Confirm the management API schema and versioning rules.
- Decide whether the CLI remains shell-based or becomes its own package while
  preserving its public commands.
- Add per-component development commands to the root `Makefile`.

Complete when every app and shared package has a documented purpose, public
interface, test command, and allowed dependencies.

### 3. Move files without behavior changes

Status: complete

- Move the macOS application to `apps/macos`.
- Move CLI entry points and CLI-only support code to `apps/cli`.
- Group harness components under `packages/app-state`.
- Group the API executable and schema under `packages/management-api`.
- Move reusable Nix configuration under `nix` while retaining the root flake.
- Relocate installation, release, and development scripts under `tools`.
- Update imports, paths, documentation, tests, and packaging scripts.

Complete when the pre-move and post-move commands produce equivalent results,
all existing tests pass, and the migration contains no intentional feature
changes.

### 4. Add scoped automation

Status: complete

- Run Swift tests and app packaging checks only when macOS app or shared API
  paths change.
- Run harness tests when app-state, API, or relevant Nix paths change.
- Run Nix formatting, evaluation, and VM tests for Nix configuration changes.
- Keep the macOS release workflow app-specific and tag-driven.
- Add explicit versioning and release rules for future applications.
- Add a lightweight repository-wide contract check for management API schema
  compatibility.

Complete when pull requests receive the smallest sufficient test set, shared
contract changes validate every consumer, and each distributable application
has an isolated release workflow.

## Decision log

- 2026-10-04: Adopt an explicit monorepo structure rather than splitting the
  macOS app and configuration harness into separate repositories.
- 2026-10-04: Keep the management API as the boundary between declarative Nix
  state and user-facing applications.
- 2026-10-04: Merge features independently before beginning directory moves.
- 2026-10-04: Keep the existing shell CLI for compatibility and isolate it in
  `apps/cli`; future rewrites must preserve its public command surface.
- 2026-10-04: Treat the post-install TUI as an independent application with
  Node 26.4+, a clean build, and its own path-scoped workflow.
