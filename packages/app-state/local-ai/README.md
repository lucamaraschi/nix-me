# Local AI recipe boundary

`recipes/pi.yaml` makes Pi Coding Agent a first-class harness application and
converges only these small, user-owned JSON files:

- `~/.pi/agent/settings.json`: portable Pi preferences, the default DS4 model,
  and the local `pi-ds4` package declaration;
- `~/.pi/ds4/settings.json`: non-secret pi-ds4 launch settings.

Both entries use deterministic JSON serialization, mode `0600`, pointer
allowlists, and `deep_merge`. Keys absent from the generated values map remain
untouched. Apply uses `poke: none`: it does not signal, restart, stop, or probe
`ds4-server`.
Pi reads changes on its next start or explicit `/reload`; an already-running
DS4 process continues with its current launch settings.

The `local-ai` Nix profile is the activation boundary. It enables `apps.state`
by default and appends a `pkgs.writeText` JSON values file generated for the
configured host. The checked-in default values directory intentionally has no
`pi.yaml`, so merely loading the recipe registry cannot activate these
settings on another host.

Pi loads `~/src/ai/pi-ds4` through its native `packages` setting. This replaces
the older extension and support symlinks. `DS4_RUNTIME_DIR`, supplied by the
profile, points the package at the project checkout in `~/src/ai/ds4`. The
extension builds `ds4-server` lazily when needed; `local-ai-setup` remains an
optional eager build and validation command.

## Exclusions

The recipe does not own repositories, executables,
model manifests, model binaries or downloaded weights (including GGUF files),
partial downloads, credentials, API keys, OAuth data, tokens, caches, prompt or
session data, logs, traces, leases, lock directories, PID files, port files, or
socket state. In particular, `~/.pi/agent/auth.json` and every runtime artifact
under `~/.pi/ds4` other than `settings.json` stay outside the harness.

Secret handling is default-closed: the generated values contain no secret
field, and credentials must not be added to the profile-generated maps. The Pi
recipe refuses DS4 API keys, proxy URLs, and executable command fields.
Authentication remains in Pi's separate `~/.pi/agent/auth.json`, which is never
read or managed by the harness.

## Path assumption

The profile exports `DS4_RUNTIME_DIR` as `/Users/${username}/src/ai/ds4`,
matching its project declaration. Pi's provider and model ID are
derived from the profile's canonical `selectedModel.piModel` value (currently
`ds4/dsv4-flash-q2`) rather than duplicated in a checked-in values file.
`PI_CODING_AGENT_DIR` overrides are not represented because recipe file paths
are static.

The recipe intentionally has no top-200 catalog mapping. `pi-coding-agent` is a
Homebrew formula, while the local catalog contains cask applications and
requires each mapping to match a recipe's cask install source.
