# Local recipe catalog operations

Recipes live locally in this repository. The application-state engine treats
them as untrusted data until they pass schema and semantic validation. A
verification stamp is stronger: it represents an observed run in a macOS VM or
the app-level human harness and must never be written by an author by hand.

## Validate local recipes

```sh
nix-me-apps registry validate --recipe recipes --json
```

Validation recursively loads the supplied recipe directories, validates the
canonical JSON Schema, enforces semantic binding and ownership rules, checks that
each filename matches its recipe id, rejects duplicate ids, and inventories
unverified, pipeline-backed, and compiled-codec recipes.

## Top-200 Homebrew application map

The denominator is generated from Homebrew's official 365-day cask-install
analytics. The raw feed contains CLI tools, fonts, runtimes, and drivers, so the
catalog selects the first 200 entries whose current official cask metadata has
an `app` artifact. Every application retains its original analytics rank.

```sh
tools/update-homebrew-app-catalog.sh
nix-me-apps registry catalog-validate \
  --catalog packages/app-state/catalog/homebrew-top-200-apps.json \
  --recipe recipes --json
```

The generator extracts preference-plist and user-configuration paths from each
cask's zap stanza. These signals produce a reviewable initial classification:
`defaults_dominant`, `file_driven`, `hybrid`, or `cloud_or_opaque`. Curated facts
and local recipe links live in `packages/app-state/catalog/homebrew-behavior-overrides.json`, so a
refresh updates rankings and manifest evidence without erasing research.

Confidence is part of the data. `high` means a curated mechanism, `medium` is a
Homebrew-path inference that capture still needs to confirm, and `low` means the
cask exposes only an app artifact and requires direct investigation.

The full ranked table is
[`packages/app-state/catalog/homebrew-top-200-apps.md`](../packages/app-state/catalog/homebrew-top-200-apps.md), backed
by JSON validated against [`packages/app-state/catalog/catalog.schema.json`](../packages/app-state/catalog/catalog.schema.json).

To choose a high-value local recipe candidate:

```sh
jq -r '.applications[] |
  select(.local_recipe == null) |
  select(.behavior.mechanism == "defaults_dominant" or
         .behavior.mechanism == "file_driven") |
  [.rank, .cask, .behavior.mechanism, .behavior.confidence] | @tsv' \
  packages/app-state/catalog/homebrew-top-200-apps.json
```

Capture or research that application, add `packages/app-state/recipes/<id>.yaml` and its values,
then add a curated override containing the mechanism, note, and `local_recipe`
link. Regenerate the catalog and metric. Everything remains in this repository;
there is no separate recipe-registry checkout or release cycle.

## Measure configurability residue

```sh
nix-me-apps registry catalog-metric \
  --catalog packages/app-state/catalog/homebrew-top-200-apps.json \
  --recipe recipes \
  --json > packages/app-state/metrics/zero-click.json
```

An app is zero-click only when its linked local recipe has every entry declaring
`confirm: none`. An app whose highest residue is `one_click` counts separately,
as does any app containing `full_manual`. Apps without a local recipe are
`uncovered_apps`, so the metric cannot be inflated by measuring only completed
recipes. CI also rejects catalog links whose recipe ID or cask does not match.

## Compiled codecs

Declarative pipelines remain the default. A genuinely non-compositional format
can implement the `nix_me_codec::Codec` trait and register an exact id/version in
the engine's compile-time registry. Dynamic libraries are intentionally not
loaded: the installed engine remains one runtime-free binary and an untrusted
recipe cannot choose arbitrary native code. CI runs:

```sh
nix-me-apps registry codec-smoke --json
```

The registry is empty in v1 because all shipped artifacts use declarative
primitives.

## UTM verification

The existing VM harness accepts an optional recipe/value pair. With local source
it streams the repository into the VM while excluding `.git` and `packages/app-state/engine/target`,
installs nix-me, validates the recipe, applies it, and requires the immediate
diff to return either fully converged (`0`) or manual-residue-only (`3`):

```sh
./tests/vm/vm-test.sh \
  --base-vm="macOS Tahoe - base" \
  --vm-user=admin \
  --source=local \
  --onsuccess=delete \
  --onfailure=keep \
  --app-state-recipe=packages/app-state/recipes/rectangle.yaml \
  --app-state-values=packages/app-state/values/rectangle.yaml \
  --app-state-only=rectangle
```

The `vm-app-state` workflow exposes this as a manual job for a self-hosted runner
labeled `self-hosted`, `macOS`, `ARM64`, and `utm`. Failed VMs are retained for
inspection; successful ephemeral clones are deleted.

T0/T1 and registry validation run automatically on hosted Linux and macOS CI.
T2 uses disposable `com.nix-me.test-*` preference domains. T3 still requires an
actual application UI: Rectangle must visibly change and Raycast must accept the
generated import. Only that verification authority may replace `verified: null`
with a stamp containing macOS version, app version, date, and harness revision.

Hosted CI also runs the shipped Raycast pipeline smoke against synthetic plain
and AES-wrapped artifacts. It decodes and re-encodes the exact registry pipeline
and requires a deliberately truncated envelope to fail. The manual UTM/T3 job
remains the separate authority for proving that Raycast accepts the artifact.
