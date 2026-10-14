# Nix input update policy

## Purpose

Flake input updates are proposed as reviewed pull requests. Automation may
refresh `flake.lock`, but it must not activate a configuration, merge its own
pull request, or change the cache trust boundary.

## Binary cache policy

- Nix-Me relies on the official `https://cache.nixos.org/` substituter and its
  standard NixOS signing key. This is the default supplied by Nix.
- The repository does not operate, publish to, or trust a project-specific
  binary cache. GitHub runners and managed hosts must not add an unowned Cachix,
  Attic, or other substituter merely to make an update pass faster.
- A cache miss is allowed. It can cause a package to build from source, and that
  build cost is review evidence rather than authorization to widen trust.
- Adding a cache requires a separate reviewed change that names its owner,
  signing-key custodian, write principals, retention policy, revocation process,
  and the exact package scope it is intended to serve.
- Cache credentials, if introduced later, must be environment-scoped GitHub
  secrets. Pull-request workflows from forks must never receive write keys.

## Complete host matrix

`nix/host-matrix.json` is the reviewed inventory of flake host outputs. The
validator rejects an output that exists only in the flake or only in the
manifest, then evaluates the system derivation for every listed Darwin, NixOS,
and standalone Home Manager configuration.

Run the same gate locally with:

```bash
make check-host-matrix
```

This is evaluation, not activation: it creates derivations but never runs
`darwin-rebuild switch`, `nixos-rebuild switch`, Homebrew, or project sync.
Adding or removing a host therefore requires updating `flake.nix` and
`nix/host-matrix.json` in the same pull request.

## Automated update flow

`Flake input updates` runs every Monday at 16:17 UTC and can also be dispatched
manually. It starts from `main`, runs `nix flake update`, and, when the lock file
changes, force-updates the dedicated `automation/flake-inputs` branch using a
lease. It then creates or refreshes a draft pull request and explicitly
dispatches `Nix configuration` on that exact branch.

The explicit dispatch is required because GitHub intentionally suppresses most
new workflow events caused by its own `GITHUB_TOKEN`. It ensures the generated
commit receives the same full-host evaluation and managed-package builds as a
human-authored Nix change.

Before marking an update pull request ready, a reviewer must:

1. Inspect every input revision change and upstream release notes where the
   change is material.
2. Require a green `Nix configuration` run for the current pull-request commit.
3. Review unexpected source builds against the binary cache policy above.
4. Confirm that no host disappeared from `nix/host-matrix.json` merely to make
   evaluation pass.
5. Merge normally through branch protection. Never enable auto-merge for the
   automation branch.
