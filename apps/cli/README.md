# nix-me CLI

The shell CLI is the interactive and scripting entry point for managing a
nix-me checkout. Its public executable is `apps/cli/bin/nix-me`.

The CLI may call the versioned management API and app-state engine, but it must
not duplicate their JSON contracts or convergence logic. Shared shell helpers
belong in `apps/cli/lib` only when they implement CLI behavior.

Run its integration checks from the repository root:

```sh
make test-cli
```
