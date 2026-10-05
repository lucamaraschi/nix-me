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
