# nix-me for macOS

A SwiftUI dashboard for inspecting and managing the nix-me configuration on the current Mac.

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

## App settings and configuration

**App Settings** manages preferences inside installed apps, not which apps are
installed. Opening the screen automatically checks supported, allowlisted
preferences without saving anything. App cards are grouped into **Changes to
keep**, **Not saved yet**, and **Saved settings**. Failed checks appear under
an expandable **Apps need attention** notice; other installed apps are collapsed
by default. Leaving App Settings stops the automatic check after the current app.
Apps that have not created supported preferences yet are under **Nothing to save
yet**, not reported as failed checks or matching copies.

Open an app to see a save summary and preferences grouped by their documented
app sections, such as General or Layout. The preview distinguishes the preferences
on **This Mac** from the saved copy in the **Repository**, without pretending to
show old values the API does not expose. **Save settings** keeps a first
copy; **Save changes** updates one already saved. This is the only primary action
below the preview. Unchanged preferences are collapsed; reviewed text files show
their contents directly rather than escaped JSON. Background checking stops after the current app while an
inspector is open and resumes unchecked apps when it closes.

The default location is **This Mac**. Click the location beside **Keeping settings
for** to choose **All machines** or an active **Profile**. Changing the location
clears reviews and checks against the new saved copy; cancelling changes nothing.
The app detail's **Save for** menu changes the same destination without returning
to the landing page, and immediately checks against that destination again.

**Details** in the app header lists saved copies and other active
sources separately. Groups refer to the selected `settings.json`, not inherited
profiles or built-in defaults. Unchecked and failed apps are never treated as
matching. JSON, file paths, and diagnostics live in Details, not the normal preview.
Details uses explicit accessible sections, with **Show JSON** for the reviewed
export and **Copy details** for a local plain-text report. Opening it reads no
additional application files. Access-denied errors explain that retrying does
not change macOS permissions; Nix Me never grants itself broader access.
**Resolve Access** opens an inline guide, identifies the source and the exact
running Nix Me bundle, and offers Privacy Settings and optional Full Disk Access
shortcuts. The latter is explicitly described as broader access, not a requirement.
Returning from System Settings triggers one new settings read; **Check Access**
can also verify it manually. Only a fresh successful preview reports readable
settings. Partial denials, missing preferences, and unrelated errors stay distinct.
Filesystem ownership/ACL errors get a different guide with no Full Disk Access
shortcut. The flow never runs sudo, edits permissions, or saves preferences.
Manual-only settings are not presented as read failures; actual unread sources
remain visible as warnings in the preview. Saving is not a full backup of the app.

**Check All Apps Again** in the options menu repeats automatic checks.
Reviewed source files require **Allow & Preview** individually. Approval is remembered
for the current app session; the permission prompt goes away, and the refresh
button in the app header checks for newer changes. A failed read offers **Try again**
(or **Resolve Access** for a permission denial)
without asking for permission again. Reopening the app's details, refreshing, or choosing a different
save destination does not ask again. A different checkout, machine, or set of settings
sources requires fresh permission, as does restarting Nix Me. These files remain
excluded from background checks; permission does not automatically save anything.
Each review shows current
redacted values and whether each property is missing, different, or matching at
the destination. Saved-only properties are preserved, not removed or echoed.
Saving refuses stale previews if preferences or the
destination changed. It does not commit, push, or apply the system.

**Overview** independently summarizes selected-destination exports, session
comparisons, and last-known Git status. Refreshing or changing destination clears
comparisons. Use the repository-folder action to review files with your Git
client, then commit and push. **Changes** remains the separate system-wide apply
flow. Private state stays outside the capture boundary.
Engine information, enabling/applying saved settings, apply history, and
verification notes live in **Apply & Diagnostics**, away from the save flow.

**Configuration** explains the checkout's shared defaults, hardware type,
selected profiles, and machine-specific file. Select a file to inspect it in
**Files & Dependencies**, follow references, open it in an editor, or reveal it
in Finder. The map is a static scan, not evaluated Nix merge order or live system
state; dynamic imports may be incomplete. It never changes files automatically.

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

Development builds now reuse a pinned certificate identity when one is available.
See [stable signing](../../../docs/MACOS_DISTRIBUTION.md#stable-signing-and-privacy-approvals)
for local and Nix-managed behavior. Code signing does not grant macOS privacy
permissions; users must still approve access themselves.

## Machine drift

The overview now distinguishes repository changes from local machine changes.
Open **Changes > Machine Drift** (or **Review Mac Changes** on Overview) to compare
live Homebrew selections and Home Manager-managed dotfiles with the selected
configuration. New repository declarations are pending changes, not local drift.

Select only the differences you want to handle:

- **Review Save > Save to Configuration** is the primary Mac-to-repository flow.
  Each app/tool row has a **Save to** dropdown: shared defaults, this exact
  machine type, an active profile, or this machine (default). Expand
  **Destination details** for the source module, save file, and affected hosts.
  Different items can use different destinations in one review/save. Review
  groups the items by destination and evaluates their combined effect on each
  affected host, preserving exceptions. Dotfiles remain machine-only but can
  be saved alongside software going to shared profiles.
  It previews the exact file diff and saves under `config/machine-state/`.
  It does not change this Mac,
  apply the system, commit, or push. The saved-state card shows files ready for
  your normal Git workflow, using local metadata rather than claiming a fresh
  remote check. For recognized older checkouts, the review also includes the
  missing support module and import; Nix validation failures roll back those
  edits. Custom or ambiguous module layouts are never overwritten.
- **Other Action > Discard Selected Mac Changes** is the opposite direction.
  It reinstalls missing packages, uninstalls selected
  undeclared packages, or restores selected files. Confirm the effects first.
  File entries are renamed to adjacent `.nix-me-backup-<id>` backups before
  replacement. Homebrew cleanup, forced dependency removal, and `--zap` are not
  used. Results are verified against a fresh scan. It never saves to the repository.

Both actions reject stale reviews. Scans never claim that excluded or failed
checks matched. Read-only scans run on refresh; nothing is reconciled in the
background. Homebrew dependencies are excluded from unmanaged additions.
Homebrew versions are not pinned. Private paths, directory-managed trees,
unmanaged files, App Store apps, and system preferences are outside this first
pass; reviewed application preferences remain in **App Settings**.
