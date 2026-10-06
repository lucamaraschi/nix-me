# Local AI recipe boundary

`recipes/local-ai.yaml` converges only these small, user-owned JSON files:

- `~/.pi/agent/settings.json`: the default Pi provider and model;
- `~/.pi/ds4/settings.json`: non-secret pi-ds4 launch settings.

Both entries use deterministic JSON serialization, mode `0600`, and
`deep_merge`. Keys absent from `values/local-ai.yaml` remain untouched. Apply
uses `poke: none`: it does not signal, restart, stop, or probe `ds4-server`.
Pi reads changes on its next start or explicit `/reload`; an already-running
DS4 process continues with its current launch settings.

## Exclusions

The recipe does not own repositories, extension/support links, executables,
model manifests, model binaries or downloaded weights (including GGUF files),
partial downloads, credentials, API keys, OAuth data, tokens, caches, prompt or
session data, logs, traces, leases, lock directories, PID files, port files, or
socket state. In particular, `~/.pi/agent/auth.json` and every runtime artifact
under `~/.pi/ds4` other than `settings.json` stay outside the harness.

Secret handling is default-closed: the committed values contain no secret
field, and credentials must not be added to either managed values map. Use the
credential mechanism supported by Pi or a separately protected `DS4_API_KEY`
environment source instead. Plan output shows the structured contents of a
managed file, so migrate any pre-existing `apiKey` field out of
`~/.pi/ds4/settings.json` before running plan/apply; merge preservation is not a
redaction boundary.

## Path assumption

The DS4 runtime is `/Users/batman/src/ai/ds4`, matching the current `local-ai`
profile and project declaration (`~/src/ai/ds4`) for repository hosts whose
configured username is `batman`. A host with a different username or checkout
location must override `local-ai.ds4_settings.runtimeDir` in its values before
apply. `PI_CODING_AGENT_DIR` overrides are not represented because recipe file
paths are static.

The recipe intentionally has no top-200 catalog mapping. `pi-coding-agent` is a
Homebrew formula, while the local catalog contains cask applications and
requires each mapping to match a recipe's cask install source.
