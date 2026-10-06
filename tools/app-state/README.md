# App-state recipe candidate scoring

`score_recipe_candidates.py` ranks unsupported apps from the checked-in Homebrew
top-200 catalog. It reads the version 1 catalog and zero-click metric, rejects
inconsistent or incomplete inputs, excludes every non-null `local_recipe`, and
writes the version 1 artifact defined by
`packages/app-state/metrics/recipe-candidates.schema.json`.

The score is bounded to `0..100` and uses integer basis-point arithmetic before
serialization:

```text
impact * 0.45 + feasibility * 0.40 + (100 - risk) * 0.15
```

Impact combines normalized install volume (70%) and top-200 catalog reach (30%).
Feasibility and risk use the versioned mechanism, confidence, evidence, and
path-signal rubrics embedded under `policy` in the generated artifact. Candidate
rows include their component rationale. Equal totals are ordered by catalog rank,
then cask name.

For the H-030 dimensions, Homebrew's 365-day installs are an explicit proxy for
installed-profile frequency because the repository has no profile telemetry.
Mechanism and path signals represent configurability, confidence/evidence model
implementation confidence, and mechanism/path complexity estimates T3 cost.

Generate or validate the checked-in artifact from the repository root:

```sh
python3 tools/app-state/score_recipe_candidates.py
python3 tools/app-state/score_recipe_candidates.py --check
python3 -m unittest discover -s tools/app-state -p 'test_*.py'
```

The output intentionally has no generation timestamp. Source SHA-256 values and
the catalog analytics window identify its inputs without making repeated runs
non-deterministic.
