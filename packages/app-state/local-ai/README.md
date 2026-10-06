# Local AI recipe boundary

`recipes/local-ai.yaml` converges only these small, user-owned JSON files:

- `~/.pi/agent/settings.json`: the default Pi provider and model;
- `~/.pi/ds4/settings.json`: non-secret pi-ds4 launch settings.

Both entries use deterministic JSON serialization, mode `0600`, and
`deep_merge`. Keys absent from the generated values map remain untouched. Apply
uses `poke: none`: it does not signal, restart, stop, or probe `ds4-server`.
Pi reads changes on its next start or explicit `/reload`; an already-running
DS4 process continues with its current launch settings.

The `local-ai` Nix profile is the activation boundary. It enables `apps.state`
by default and appends a `pkgs.writeText` JSON values file generated for the
configured host. The checked-in default values directory intentionally has no
`local-ai.yaml`, so merely loading the recipe registry cannot activate these
settings on another host.

## Exclusions

The recipe does not own repositories, extension/support links, executables,
model manifests, model binaries or downloaded weights (including GGUF files),
partial downloads, credentials, API keys, OAuth data, tokens, caches, prompt or
session data, logs, traces, leases, lock directories, PID files, port files, or
socket state. In particular, `~/.pi/agent/auth.json` and every runtime artifact
under `~/.pi/ds4` other than `settings.json` stay outside the harness.

Secret handling is default-closed: the generated values contain no secret
field, and credentials must not be added to the profile-generated maps. Use
the credential mechanism supported by Pi or a separately protected
`DS4_API_KEY` environment source instead. Plan output shows the structured
contents of a managed file, so migrate any pre-existing `apiKey` field out of
`~/.pi/ds4/settings.json` before running plan/apply; merge preservation is not
a redaction boundary.

## Path assumption

The profile generates `runtimeDir` as `/Users/${username}/src/ai/ds4`, matching
its project declaration at `~/src/ai/ds4`. Pi's provider and model ID are
derived from the profile's canonical `selectedModel.piModel` value (currently
`ds4/dsv4-flash-q2`) rather than duplicated in a checked-in values file.
`PI_CODING_AGENT_DIR` overrides are not represented because recipe file paths
are static.

The recipe intentionally has no top-200 catalog mapping. `pi-coding-agent` is a
Homebrew formula, while the local catalog contains cask applications and
requires each mapping to match a recipe's cask install source.
