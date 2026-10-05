# Management API

`nix-me api` is the versioned, machine-readable interface used by the native
macOS application. JSON is written to stdout; diagnostics are represented in
the `warnings` array so clients can render partial results.

## Endpoints

```bash
nix-me api snapshot   # Complete dashboard state (default)
nix-me api status     # Host, configuration, Git, and tool health
nix-me api inventory  # Desired, applied, and installed software
nix-me api updates    # Available Nix, Homebrew, and Mac App Store updates
nix-me api projects   # Configured repository state
nix-me api manifest   # Current desired Nix manifest
```

The top-level `schemaVersion` is currently `1`. Consumers must reject versions
they do not understand rather than silently interpreting changed fields.

## Desired and applied state

The `management-api.nix` module evaluates a pure desired manifest and installs
the same data at `/etc/nix-me/manifest.json` during `make switch`. The API
compares host settings, software, and projects from those manifests:

- `current`: desired and applied configuration match.
- `pending`: evaluated configuration differs from the active manifest.
- `unknown`: one of the manifests is unavailable, normally before the first
  switch containing management API support.

The comparison includes the evaluated flake source and `flake.lock` hashes, so
package input changes and non-package Nix setting edits remain pending until a
successful activation.

Git state is reported separately. `dirty`, `ahead`, and `behind` describe
whether configuration changes need committing, pushing, or pulling; they do
not imply that the system needs activation.

## Environment

- `NIX_ME_CONFIG_DIR` overrides configuration discovery.
- `NIX_ME_HOSTNAME` evaluates another configured host.
- `NIX_ME_APPLIED_MANIFEST` overrides the active manifest path for testing.
- `NIX_ME_SKIP_UPDATES=1` skips all network-backed update queries.

Nix updates are detected by resolving inputs into a temporary candidate lock
file and comparing revisions. The repository's real `flake.lock` is never
modified by an API check.

## Update actions

The native app sends selected update objects as JSON on stdin to
`nix-me action update`. The action backend rejects unknown update kinds and
unsafe package names, then maps accepted items to fixed operations:

- Nix inputs: targeted `nix flake update`; activation is still required.
- Homebrew formulae and casks: grouped `brew upgrade` operations.
- Mac App Store apps: one authenticated `mas update` operation per batch.

Actions return structured per-item results. `NIX_ME_ACTION_DRY_RUN=1` validates
and reports intended operations without changing packages or `flake.lock`.

`nix-me action apply` runs the existing `switch-fast` activation path after a
native macOS administrator prompt. The app passes the evaluated hostname and
username explicitly, skips duplicate Homebrew update checks, waits for
activation to finish, and then refreshes desired-versus-applied state.
