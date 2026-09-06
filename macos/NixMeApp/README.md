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

The app displays desired and applied state, Git synchronization, managed
software, updates, and configured projects using `nix-me api snapshot`.
Available updates can be applied individually, as a selection, or as one batch.
Nix input updates change `flake.lock`; the dashboard then offers an explicit
Apply Configuration step with native administrator approval.

The menu bar indicator checks every 30 minutes and displays the total number of
available Nix input, Homebrew, and Mac App Store updates. Opening it shows a
compact system summary and supports manual refresh or opening the dashboard.

Nix Me also checks for application updates through Sparkle. Production builds
are distributed as signed and notarized DMGs from GitHub Releases, with an
optional Homebrew cask. See [macOS distribution](../../docs/MACOS_DISTRIBUTION.md)
for release credentials and workflow details.
