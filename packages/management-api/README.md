# Management API

This package is the versioned process boundary used by the native app, CLI,
and future clients. Commands emit JSON on stdout and diagnostics on stderr.

- `nix-me-api` provides read-only snapshots and focused views.
- `nix-me-action` validates and performs explicit mutations.
- `nix-me-details` resolves package metadata lazily.

Application settings are captured through `settings-preview` and written only
after an explicit `settings-save` action. These actions can create or update
files under `config/app-state/{shared,profiles,machines}`; they never stage,
commit, or push repository changes. Local evaluation and apply include newly
created settings files before they are committed.

Settings previews include `comparison.properties`: JSON Pointer paths, redacted
`currentValue` JSON strings, and `notSaved`, `different`, `matching`, or `preserved` status
against the selected destination only (not inherited values). Arrays and empty
objects are atomic properties; an empty object cannot clear saved children under
the merge contract and is marked `preserved`. `preservedCount` counts saved-only properties;
these are not deleted or exposed in the preview. `preview` contains the redacted
capture, not the merged destination, so unrelated saved secrets are never echoed.
Clients should submit the returned `reviewToken` with `settings-save`. A changed
capture or destination returns `review_outdated` without writing. The native app
requires this token. Legacy CLI requests without a token remain supported.

Configuration sources optionally include `propertyPaths` for JSON values files,
without their values. Built-in defaults are not user exports. The native app
automatically compares structured, allowlisted preferences when App Settings is
opened; reviewed source files are excluded and still require individual approval.
Comparison results are session-local and cleared
when refreshing or changing destination. Git status is last-known upstream data,
not evidence of a network fetch or successful publishing.

An empty capture returns `no_preferences` only when every skipped entry is
explicitly identified by the engine as `no_declared_values` or `file_missing`.
This is an informational state, not a successful comparison or permission to
save. Unknown reasons and read failures retain `nothing_captured`. Neither path
modifies saved settings, and clients must never infer that an unchecked app
matches the repository.

`appStateSettings.applications` merges the recipe registry with user-installed
bundles found in `/Applications` and `~/Applications`. Recipe-backed entries
include their recipe path and active built-in, shared, profile, and machine
value sources. Unmanaged installed bundles are included with
`recipeAvailable: false` and cannot be captured until a recipe is added.
Each recipe-backed entry also exposes `exportableSettings`, the exact
preference keys, structured files, and command-managed lists that can be
converted into harness JSON. An empty list is an explicit non-exportable
boundary, not an invitation for clients to inspect application data directly.
Entries with `requiresConfirmation: true` are reviewed source files. Clients
must obtain explicit approval before sending `confirmReviewedText: true` to
`settings-preview` and must carry the same confirmation into `settings-save`.

`harness-enable` changes the per-machine `enabled` marker to `true` and reports
that a configuration apply is required. It does not itself apply, stage, commit,
or push the change; the native app follows it with the normal Apply confirmation.

Projects are added through `project-preview` and `project-save`. The actions
write validated declarations under `config/projects/{shared,profiles,machines}`
and never clone, sync, apply, stage, commit, or push. Repository network access
remains an explicit `sync-projects` action.

Clients must invoke these executables rather than reading generated manifests,
Nix modules, or application-state files directly.

The current snapshot contract is version 1 and is recorded in
`schema/snapshot-v1.schema.json`. Additive fields may be introduced within a
version. Removing fields, changing their meaning, or changing their type
requires a new schema version and coordinated client fixtures.

`localAI` is an optional additive snapshot member for older-client
compatibility. New API responses always provide its version 1 read-only status,
and `nix-me-api local-ai` provides the focused view. Component states distinguish
known absence (`missing`, `notBuilt`, `stopped`, or `drifted`) from
`unavailable`; refresh is bounded and never builds DS4, downloads a model,
starts or stops a server, clones a checkout, applies harness state, or launches
an app.

Model download, cancellation, checksum, and cleanup are intentionally not part
of this status contract. The separate `local-ai-model-start`,
`local-ai-model-status`, and `local-ai-model-cancel` actions expose a private,
inspectable operation record. Only start launches the downloader. Status never
writes state or cleans files; it synthesizes a failed view for a dead worker.
Explicit start or cancel performs stale cleanup. Completed artifacts replace the
configured model atomically; failures and cancellation preserve the previous
model.

Run the contract tests from the repository root:

```sh
make test-api test-actions test-details
```

## Selective machine reconciliation

`bin/nix-me-drift` is the version 1 JSON boundary for `scan`, `preview`, `prepare`, `keep`,
and `restore`. It requires Python 3.9+, `NIX_ME_CONFIG_DIR`, and
`NIX_ME_HOSTNAME`, and runs as the logged-in user, never root. Nix-built app
bundles include Python in their runtime path. `NIX_ME_APPLIED_MANIFEST` may
override `/etc/nix-me/manifest.json` for tests.

`scan` compares a freshly evaluated desired manifest, the applied manifest,
and live Homebrew/file state. It returns `token`, `configurationToken`,
`coverage`, `items`, `warnings`, and the machine-only save `destination`.
Coverage is explicit: a failed tool, unrealized source, private path, or
unsupported directory is never equivalent to a successful comparison.

Other commands accept JSON on stdin: `{ "token": "...", "ids": ["..."] }`.
Select 1-100 IDs from the latest scan. The backend regenerates all paths and
commands from that scan; callers cannot supply mutation paths or shell code.
`preview` returns selected files' complete current/expected text, a unified
diff, and `reviewToken`. `prepare` previews every proposed repository edit and
returns a `proposalToken`; `keep` requires that token for all selections.
Preparing a file save reads only the selected managed files and rejects obvious
credentials. A recognized older checkout may receive the reviewed support
module and import along with its reviewed JSON file. Custom modules and
ambiguous layouts are rejected. Writes recheck original bytes and evaluate Nix;
validation failures roll back our writes without overwriting concurrent edits.
Content remains plain text in
the repository and Nix store; detection is not a substitute for human review.

`restore` confirms each selected item still matches the review immediately
before acting. It backs up file entries, runs scoped Homebrew actions without
force/zap/autoremove, and verifies the resulting state. Partial failures are
reported per item; a successful process exit alone is not proof of restoration.
Actions serialize per checkout, never stage/commit/push, and never silently
promote a machine override to a shared profile. `scan.publication` describes
saved-file Git status using local metadata only; it never fetches or claims that
the remote is current. Saved results list `filesWritten` for review and publishing
in the user's Git client.

`scan.destinations` lists the evaluated layers for this host, their original
source modules, overlay paths, and exact host membership. Send
`destinationsByItem` in `prepare` and `keep`, mapping every selected item ID to
its destination ID. Missing/extra entries and inactive destinations are rejected.
For older clients, a single `destinationID` still applies to the whole batch;
omitting both fields means this machine. Do not combine the two fields. A client
cannot supply arbitrary paths or inactive profiles. The proposal token binds
the destination, edits, and per-host impact, not just the selected packages.
Mixed saves evaluate all destination states together on every affected host,
without writing files first. Review includes grouped `destinations`, the exact
`destinationsByItem` map, and per-host effects for only the items reaching that
host. All destination files are written in one rollback-protected action. More
specific exceptions on other hosts are preserved and explained; an exception
on this host blocks an ineffective save. Profile conflicts fail validation.
Dotfiles cannot be saved to shared destinations. A host/type/profile membership
change invalidates review. The app does not move existing saved overrides when
choosing a new destination.

Test without modifying the current machine:

```sh
python3 tests/integration/test_machine_drift.py
nix eval --impure --json --file tests/integration/machine-state-eval.nix
```
