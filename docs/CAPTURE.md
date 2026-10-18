# Capturing application state

Capture observes the preference-domain delta produced by a GUI change and emits
both artifacts needed by the app-state layer: a registry recipe fragment and a
profile-values fragment. Secret-looking keys and high-entropy strings are removed
unless explicitly included.

```sh
nix-me apps capture Rectangle --domain com.knollsoft.Rectangle --json
```

Keep the prompt open, change one setting in the app, return to the terminal, and
press Enter. Add `--include-key exactKey` only after reviewing a reported omission.
`--watch` polls both AnyHost and CurrentHost preferences while you walk through
a settings pane. Newly observed keys are logged as they change; press Enter to
finish and emit one batched fragment set.

Unknown export formats can be inspected on macOS or Linux:

```sh
nix-me apps capture --sniff export.rayconfig --json
```

The sniffer peels recognizable header, gzip, container, plist, JSON, YAML, SQLite,
TOML, base64, and OpenSSL-envelope layers. It includes the decoded model and any
opaque header bytes when available, and terminates with an honest `opaque` or
`probably_encrypted` verdict when it cannot prove the next transform.

Raycast scheduled exports can feed a continuously updated, diffable JSON file:

```sh
nix-me apps capture --sniff backups/latest.rayconfig --watch \
  --output captured/raycast.json
```

Watch mode emits JSON Lines with `--json`. Add `--commit` only in a dedicated
capture worktree; each changed decoded output is staged and committed locally as
`capture: update <path>`. The watcher never pushes commits.

The native app uses a separate current-values snapshot intended for known recipes:

```sh
nix-me apps snapshot \
  --recipe packages/app-state/recipes \
  --only rectangle --json
```

Snapshot reads only state declared by the recipe. Typed defaults, structured
files, and command-managed lists are supported. Unstructured text, generated
imports, and manual steps are reported as skipped. Secret-like keys and
high-entropy values are removed before the management API can preview or save
the result.

The native Harness screen presents this capability as an application catalog,
not a picker. It includes installed applications without recipes so coverage is
visible, but enables Review and Save only for installed applications with a
capturable recipe. The detail pane identifies every active values file before a
new shared, profile, or machine-scoped configuration is saved.
