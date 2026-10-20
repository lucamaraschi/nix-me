# nix-me for macOS

A read-only SwiftUI dashboard for the nix-me configuration on the current Mac.

## Run

From the repository root:

```bash
make app-run
```

This creates and opens `build/Nix Me.app`. For development, open `Package.swift`
in Xcode. The app discovers the configuration from
`NIX_ME_CONFIG_DIR`, a previously selected folder, the current directory,
`~/.config/nixpkgs`, or `~/src/lm/nix-me`, in that order.

Before the dashboard loads, Get Started validates the configuration checkout
and required commands. It can select an existing checkout, clone the public
repository to `~/.config/nixpkgs`, or update an outdated Git checkout.
The update rebases local commits and temporarily stashes tracked changes so
machine-specific work is retained. Healthy command details and optional
integrations remain available as expanded diagnostics without competing with
the action that unblocks the app. Once the configuration is ready, onboarding
disappears from the sidebar.

## First installation

Interactive `install.sh` runs only the prerequisite bootstrap in Terminal and
then launches a lightweight, locally built variant of this app with
`--first-install`. The native flow detects the Mac, loads an existing machine
definition or creates a validated new one, presents composable profiles, shows
the complete plan, and drives build, administrator-approved activation, and
verification without modal error alerts. The lightweight setup package omits
the app-state engine to reduce first-build work; the activated system installs
the complete managed app when `apps.manager.enable` is enabled.

Use `USE_NATIVE_INSTALLER=0 ./install.sh` to exercise the terminal-only
fallback used by automation and recovery.

The app displays desired and applied state, Git synchronization, managed
software, updates, and configured projects using `nix-me api snapshot`.
Available updates can be applied individually, as a selection, or as one batch.
Nix input updates change `flake.lock`; the dashboard then offers an explicit
Apply Configuration step with native administrator approval.

Application Settings marks each installed app as Exportable, Manual file, or
Not exportable. Exportable apps show the exact preferences, structured files,
and command-managed lists that can be reviewed and saved into scoped harness
JSON. Reviewed source files are called out separately and require approval
before the app reads their exact contents; opaque and credential-bearing state
remains outside that boundary.

The menu bar indicator checks every 30 minutes and displays the total number of
available Nix input, Homebrew, and Mac App Store updates. Opening it shows a
compact system summary and supports manual refresh or opening the dashboard.

Nix Me also checks for application updates through Sparkle. Production builds
are distributed as signed and notarized DMGs from GitHub Releases, with an
optional Homebrew cask. See [macOS distribution](../../../docs/MACOS_DISTRIBUTION.md)
for release credentials and workflow details.

The app bundle includes the management scripts and the matching `nix-me-apps`
engine. The bundled engine is preferred over a system installation so the UI,
recipe schema, and capture behavior stay on the same release.
