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
