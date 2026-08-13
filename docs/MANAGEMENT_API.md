# Management API

`nix-me api` is the versioned, machine-readable interface used by the native
macOS application. JSON is written to stdout; diagnostics are represented in
the `warnings` array so clients can render partial results.

## Endpoints

```bash
nix-me api snapshot   # Complete dashboard state (default)
nix-me api status     # Host, configuration, Git, and tool health
nix-me api inventory  # Desired, applied, and installed software
nix-me api updates    # Available software updates
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

Git state is reported separately. `dirty`, `ahead`, and `behind` describe
whether configuration changes need committing, pushing, or pulling; they do
not imply that the system needs activation.

## Environment

- `NIX_ME_CONFIG_DIR` overrides configuration discovery.
- `NIX_ME_HOSTNAME` evaluates another configured host.
- `NIX_ME_APPLIED_MANIFEST` overrides the active manifest path for testing.
- `NIX_ME_SKIP_UPDATES=1` skips the Homebrew update query.
