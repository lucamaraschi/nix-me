# Nix configuration

This directory owns reusable Nix modules, machine definitions, composable
profiles, project sets, and overlays. The root `flake.nix` remains the stable
workspace entry point and imports this tree.

Nix code may package workspace components through flake outputs. It must not
embed UI behavior or parse client JSON responses.

Validate it from the repository root:

```sh
make check
```
