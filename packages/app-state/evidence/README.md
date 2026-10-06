# T3 evidence

Each committed T3 run is a per-recipe JSON manifest validated against
`t3-evidence-manifest.schema.json`. A manifest identifies the exact unstamped
recipe, execution environment, application and procedure versions, required
check results, and retained artifacts with byte counts and SHA-256 digests.
Every manifest also has an explicit lifecycle. `draft` manifests are never
stamp-eligible, even when their checks pass. `final` is written only by the T3
finalizer after it revalidates the run, retained artifacts, recipe digest, and
the committed procedure and runner at the recorded harness revision.

The trust tool has no dependency beyond Bash and `jq`:

```sh
packages/app-state/evidence/tools/evidence-tool validate-manifest manifest.json
packages/app-state/evidence/tools/evidence-tool generate-stamp manifest.json recipe.yaml
packages/app-state/evidence/tools/evidence-tool stamp-recipe manifest.json recipe.yaml
packages/app-state/evidence/tools/evidence-tool verify-repository
packages/app-state/evidence/tools/t3-procedure validate
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

## Interactive procedures

The versioned procedure files are:

- `procedures/rectangle-visible-window-management.v1.json`
- `procedures/raycast-generated-import.v1.json`

The runner records the macOS version/build, architecture, application
version/build, engine version, timestamps, recipe and procedure digests,
harness revision, apply output, and idempotence output. It then prints the
procedure's visible steps and requires a named operator to enter an observation,
supply a non-empty screenshot or video, and type a per-run challenge through an
interactive terminal. There is intentionally no `--yes`, environment-variable,
or headless path for operator acceptance. The tool does not inspect the pixels
and does not claim that visible behavior occurred.

Before a real run, commit the procedure tooling and ensure these paths are clean:

```sh
git diff --exit-code -- packages/app-state/evidence tests/vm
packages/app-state/evidence/tools/t3-procedure validate
packages/app-state/evidence/tests/run.sh
```

### Rectangle in UTM

This clones the named base VM, starts the clone with a visible display, installs
the local checkout, defers the first Rectangle apply to the T3 runner, prompts
the operator, and copies the run directory back under `evidence/runs/`:

```sh
./tests/vm/vm-test.sh \
  --base-vm="macOS Tahoe - base" \
  --vm-user=admin \
  --source=local \
  --onsuccess=keep \
  --onfailure=keep \
  --t3-procedure=rectangle-visible-window-management
```

In the VM, grant Rectangle Accessibility access if prompted. Follow the printed
steps using the Rectangle menu rather than manually resizing the window, capture
the required artifact in the VM, and enter its full path at the operator prompt.

### Raycast in UTM

```sh
./tests/vm/vm-test.sh \
  --base-vm="macOS Tahoe - base" \
  --vm-user=admin \
  --source=local \
  --onsuccess=keep \
  --onfailure=keep \
  --t3-procedure=raycast-generated-import
```

Finish onboarding if needed. The apply opens the generated import and may ask
whether Raycast can be restarted. Follow the printed steps and retain one
continuous `.mov` or `.mp4` recording that shows import acceptance and then the
configured General settings. A still image is not accepted by this procedure.

### Review and finalize

The VM command reports the exact host `RUN_DIR`. A zero exit status means only
that a passing draft was collected. Review every retained file before running:

```sh
RUN_DIR=packages/app-state/evidence/runs/REPORTED_RUN_ID
RECIPE_ID=rectangle # use raycast for the Raycast procedure

packages/app-state/evidence/tools/t3-procedure collect-draft "$RUN_DIR"
jq '{lifecycle, recipe, environment, application, procedure, run, result, artifacts}' \
  "$RUN_DIR/draft-manifest.json"

mkdir -p packages/app-state/evidence/manifests
packages/app-state/evidence/tools/t3-procedure finalize \
  "$RUN_DIR" "packages/app-state/evidence/manifests/$RECIPE_ID.json"
packages/app-state/evidence/tools/evidence-tool generate-stamp \
  "packages/app-state/evidence/manifests/$RECIPE_ID.json" \
  "packages/app-state/recipes/$RECIPE_ID.yaml"
```

`generate-stamp` is a review-only preview. After a real operator has reviewed
the final manifest and artifact, `stamp-recipe` is the separate explicit action
that replaces `verified: null`. Do not finalize or stamp a failed or incomplete
run. This repository does not bundle a production T3 run or visual artifact.

### Cleanup

The VM script prints the clone name. After the run directory has been copied,
delete the disposable clone explicitly:

```sh
UTMCTL=/Applications/UTM.app/Contents/MacOS/utmctl
VM_NAME=REPORTED_VM_NAME
"$UTMCTL" stop "$VM_NAME" 2>/dev/null || true
"$UTMCTL" delete "$VM_NAME"
```

For a failed or abandoned run, also remove its copied directory:

```sh
rm -rf packages/app-state/evidence/runs/FAILED_RUN_ID
```

Do not remove a successful run directory after finalization: the final manifest
references those retained files by path and digest.
