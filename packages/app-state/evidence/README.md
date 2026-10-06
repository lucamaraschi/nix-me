# T3 evidence

Each committed T3 run is a per-recipe JSON manifest validated against
`t3-evidence-manifest.schema.json`. A manifest identifies the exact unstamped
recipe, execution environment, application and procedure versions, required
check results, and retained artifacts with byte counts and SHA-256 digests.

The trust tool has no dependency beyond Bash and `jq`:

```sh
packages/app-state/evidence/tools/evidence-tool validate-manifest manifest.json
packages/app-state/evidence/tools/evidence-tool generate-stamp manifest.json recipe.yaml
packages/app-state/evidence/tools/evidence-tool stamp-recipe manifest.json recipe.yaml
packages/app-state/evidence/tools/evidence-tool verify-repository
packages/app-state/evidence/tests/run.sh
```

`stamp-recipe` refuses schema-invalid evidence, failed required checks, missing
or modified artifacts, and evidence for a different or changed recipe. It
normalizes only the top-level `verified` field when checking the recipe digest,
then writes a deterministic stamp containing the canonical manifest digest.

Committed evidence belongs at `manifests/<recipe-id>.json`, and its retained
files stay under this directory. Repository verification requires a one-to-one
match between those manifests and non-null recipe stamps. Failed runs may be
retained for diagnosis, but they cannot generate a stamp.
