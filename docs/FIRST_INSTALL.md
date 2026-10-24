# First Installation

The default interactive installation has two deliberately separate stages.

## Bootstrap

`install.sh` owns only work that must happen before the managed system exists:

1. Verify macOS and obtain administrator access.
2. Install or validate Apple Command Line Tools.
3. Clone or safely update the configuration checkout.
4. Install or validate Homebrew and Nix.
5. Build `nix-me-setup` locally and open it with `--first-install`.

Repository updates use `git pull --rebase --autostash`. The installer never
resets a checkout or switches an active feature branch to `main`.

## Native setup

The setup app owns choices and long-running feedback:

- Detect hostname, display name, user, and hardware type.
- Preserve a matching existing machine definition without rewriting it.
- Create a new machine through `tools/installation/create-machine.sh` when no
  definition exists.
- Enable the managed macOS app for every newly created host.
- Select composable profiles and optionally enable application-state handling.
- Review the proposed machine before changing the checkout.
- Build as the signed-in user, request native administrator approval only for
  activation, and verify completion.
- Keep failures in the installation view with expandable diagnostics and a
  retry path.

`nix-me-setup` excludes the Rust app-state engine and Sparkle. Its Info.plist
records store paths for Git, jq, Nix, and Make so a Finder-launched app does not
depend on shell initialization. It uses a separate `Nix Me Setup` bundle, then
exits after opening the complete app installed by the activated host. The
bootstrap launches a temporary copy of the setup bundle; after activation is
verified, that copy is unregistered from Launch Services and deleted when it
exits. Interrupted setup copies are retained for recovery until the next
bootstrap run replaces them. Starting setup closes any previous setup session
and the managed dashboard, and the setup-only build does not publish a menu-bar
item. The managed dashboard returns after a verified activation.

## Compatibility

Non-interactive installs and explicit positional arguments retain the existing
terminal flow. Set `USE_NATIVE_INSTALLER=0` to use that path interactively.

## Verification

```bash
make test-cli
NIX_ME_DISABLE_SPARKLE=1 swift test --package-path apps/macos/NixMeApp
nix build --no-link 'path:.#nix-me-setup'
```

Before merging, run the complete interactive path twice in a disposable macOS
VM and record bootstrap duration, the first failed or confusing step,
successful activation, and a second idempotent run.
