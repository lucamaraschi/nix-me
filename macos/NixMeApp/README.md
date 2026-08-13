# nix-me for macOS

A read-only SwiftUI dashboard for the nix-me configuration on the current Mac.

## Run

From the repository root:

```bash
make app-run
```

This creates and opens `build/Nix Me.app`. For development, open `Package.swift`
in Xcode. The app discovers the configuration from
`NIX_ME_CONFIG_DIR`, the current directory, `~/.config/nixpkgs`, or
`~/src/lm/nix-me`, in that order.

The first milestone intentionally does not modify or activate configuration.
It displays desired and applied state, Git synchronization, managed software,
Homebrew updates, and configured projects using `nix-me api snapshot`.
