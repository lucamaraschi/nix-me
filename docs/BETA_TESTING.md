# External beta testing

This guide is for invited testers running an exact nix-me beta ref on a
noncritical Mac. The beta changes system packages and can converge supported
application preferences. Use a disposable Mac or a machine with a current
backup for the first test.

## Scope and prerequisites

The beta covers the installer, Nix configuration, post-install TUI, native
macOS dashboard, and opt-in application-state harness.

- Use the exact branch, tag, or commit supplied with the test invitation.
- Have administrator access, a reliable network connection, and enough free
  disk space for the selected profiles.
- Commit or otherwise preserve local configuration changes before starting.
- Do not test the first activation on a production-critical machine.
- Never attach credentials, private repository URLs, SSH keys, tokens, or full
  configuration files to a public issue.

The examples below use `harness-next`. Replace it when the invitation specifies
a different ref.

## Record the starting point

Existing nix-me users should record their current branch and revision before
switching refs:

```bash
cd ~/.config/nixpkgs
git status --short
git branch --show-current > "$HOME/.nix-me-pre-beta-branch"
git rev-parse HEAD > "$HOME/.nix-me-pre-beta-ref"
```

Stop if `git status --short` reports changes you have not committed or backed
up. The bootstrap installer updates an existing checkout to the requested ref;
do not use it as an update mechanism for a checkout with local work.

If Rectangle is installed, preserve its current preferences before enabling the
harness:

```bash
defaults export com.knollsoft.Rectangle "$HOME/Desktop/Rectangle.before-nix-me-beta.plist"
```

## Install the beta

### Fresh Mac

Download and inspect the installer, then run it with the same ref used for the
download:

```bash
BETA_REF=harness-next
curl -fsSL "https://raw.githubusercontent.com/lucamaraschi/nix-me/${BETA_REF}/install.sh" -o /tmp/nix-me-install.sh
less /tmp/nix-me-install.sh
REPO_BRANCH="$BETA_REF" bash /tmp/nix-me-install.sh
```

The installer creates or updates `~/.config/nixpkgs` and performs the initial
system activation. Restart the terminal when it finishes.

### Existing nix-me installation

Fetch the supplied beta ref into a separate local branch, then build without
activating:

```bash
cd ~/.config/nixpkgs
git fetch origin harness-next
git switch -c beta-test --track origin/harness-next
make check
make build
```

If `beta-test` already exists, switch to it and use `git pull --ff-only` instead
of creating it again. Do not run `make update` unless the test specifically
covers updates: that target also changes `flake.lock`.

## Enable the harness

The harness remains disabled unless a host imports the beta profile. Add it to
the host's `extraModules` list in `flake.nix`:

```nix
extraModules = [
  # Existing profiles stay here.
  ./nix/hosts/profiles/beta.nix
];
```

Confirm the boundary before activation:

```bash
HOST="$(hostname -s | tr '[:upper:]' '[:lower:]')"
nix eval ".#darwinConfigurations.${HOST}.config.apps.state.enable"
make build
```

The evaluation must print `true`, and the build must succeed. Activate without
performing unrelated Homebrew update checks:

```bash
make switch-fast
```

During post-activation, `nix-me-apps` skips missing applications and manual
steps. A harness warning does not invalidate an otherwise successful Nix system
generation; inspect it with the commands below.

## Test checklist

Record the result of each check and note anything slow, unclear, or surprising.

```bash
cd ~/.config/nixpkgs
git rev-parse HEAD
nix-me-tui --version
nix-me status
nix-me doctor
nix-me harness status
nix-me harness diff
```

For the detailed read-only application plan:

```bash
nix-me apps diff \
  --recipe packages/app-state/recipes \
  --values packages/app-state/values/rectangle.yaml \
  --skip-manual --skip-missing
```

Exit status `3` means drift was found and is not an engine failure. Other
nonzero statuses should be included in the report.

Test the terminal UI with `nix-me`. For the native dashboard, build and launch
the source checkout:

```bash
make app-run
```

Verify that refresh completes, overview tiles navigate, package details open,
updates can be selected, and Apply Configuration requests administrator
approval. Open Setup and confirm that the selected checkout and command paths
match the machine. Optional missing integrations must not block the dashboard;
required missing commands must show a concrete remediation. Do not apply
package updates you are unwilling to keep.

Pull-request DMGs are Apple Silicon, ad-hoc signed, and retained for 14 days.
Until a signed and notarized prerelease is published, prefer `make app-run` and
do not disable Gatekeeper or remove quarantine attributes to run a downloaded
artifact.

## Rollback and exit

If a build fails, the active system generation has not changed. Fix or report
the build error without running activation again.

If activation succeeds but the system configuration is unusable, roll back to
the previous nix-darwin generation:

```bash
nix-me rollback
```

If the CLI is unavailable:

```bash
sudo /run/current-system/sw/bin/darwin-rebuild switch --rollback
```

To leave the beta while keeping the beta branch, remove the `beta.nix` import
and run `make switch-fast`.

To return to the previous code, first remove the `beta.nix` import from
`flake.nix`. Then switch to the recorded branch, or to the recorded revision if
the test started from a detached commit:

```bash
cd ~/.config/nixpkgs
PRE_BETA_BRANCH="$(cat "$HOME/.nix-me-pre-beta-branch")"
if [[ -n "$PRE_BETA_BRANCH" ]]; then
  git switch "$PRE_BETA_BRANCH"
else
  git switch --detach "$(cat "$HOME/.nix-me-pre-beta-ref")"
fi
make switch-fast
```

A nix-darwin generation rollback does not restore application preferences or
Homebrew upgrades. Disabling the beta profile stops future convergence but does
not undo preferences already written. Restore the Rectangle backup separately
when needed:

```bash
defaults import com.knollsoft.Rectangle "$HOME/Desktop/Rectangle.before-nix-me-beta.plist"
killall Rectangle
```

The app-state engine rolls back an interrupted apply transaction itself, but
that protection is distinct from manually leaving the beta.

## Report a problem

Open the [beta report form](https://github.com/lucamaraschi/nix-me/issues/new?template=beta-report.yml)
and include:

- Exact beta commit from `git rev-parse HEAD`.
- macOS version and architecture from `sw_vers` and `uname -m`.
- Fresh install or existing installation, and whether the beta profile was
  enabled.
- Expected behavior, actual behavior, and reproducible steps.
- The failing command, exit status, and complete relevant error text.
- Redacted output from `nix-me doctor`, `nix-me harness status`, and
  `git status --short`.
- Whether rollback was attempted and whether it succeeded.

For a Nix evaluation failure, rerun the failing build with a trace and attach
only the relevant redacted section:

```bash
HOST="$(hostname -s | tr '[:upper:]' '[:lower:]')"
nix build ".#darwinConfigurations.${HOST}.system" --show-trace
```

Native app crashes may leave reports under
`~/Library/Logs/DiagnosticReports/NixMeApp*`. Review a report for private paths
or data before attaching it.
