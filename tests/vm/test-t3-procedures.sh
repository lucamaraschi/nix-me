#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
EVIDENCE_DIR="$REPO_ROOT/packages/app-state/evidence"
RUNS_DIR="$EVIDENCE_DIR/runs"
PROCEDURE="$EVIDENCE_DIR/procedures/raycast-generated-import.v1.json"
T3_TOOL="$EVIDENCE_DIR/tools/t3-procedure"
EVIDENCE_TOOL="$EVIDENCE_DIR/tools/evidence-tool"
RECIPE="$REPO_ROOT/packages/app-state/recipes/raycast.yaml"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/nix-me-t3-tests.XXXXXX")"
CREATED_MANIFESTS_DIR=false
CREATED_FINAL_MANIFEST=false

cleanup() {
  rm -rf "$TMP" "$RUNS_DIR/synthetic-t3-$$-"*
  if [ "$CREATED_FINAL_MANIFEST" = true ]; then
    rm -f "$EVIDENCE_DIR/manifests/raycast.json"
  fi
  if [ "$CREATED_MANIFESTS_DIR" = true ]; then
    rmdir "$EVIDENCE_DIR/manifests" 2>/dev/null || true
  fi
  rmdir "$RUNS_DIR" 2>/dev/null || true
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

expect_failure() {
  local expected="$1"
  shift
  if "$@" >"$TMP/stdout" 2>"$TMP/stderr"; then
    fail "command unexpectedly passed: $*"
  fi
  grep -Fq "$expected" "$TMP/stderr" \
    || fail "expected error '$expected', got: $(cat "$TMP/stderr")"
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

recipe_sha256() {
  awk '
    BEGIN { found = 0; in_verified = 0 }
    /^verified:[[:space:]]*/ {
      if (found) exit 3
      print "verified: null"
      found = 1
      in_verified = 1
      next
    }
    in_verified && /^[^[:space:]]/ { in_verified = 0 }
    in_verified { next }
    { print }
    END { if (!found) exit 4 }
  ' "$1" | if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  else
    shasum -a 256 | awk '{print $1}'
  fi
}

make_template() {
  local template="$TMP/template"
  local artifact_sha artifact_bytes procedure_sha runner_sha recipe_sha revision
  local apply_sha apply_bytes apply_stderr_sha apply_stderr_bytes
  local idempotence_sha idempotence_bytes idempotence_stderr_sha idempotence_stderr_bytes
  local report_sha report_bytes

  mkdir -p "$template"
  printf '%s\n' 'synthetic bytes, not visual evidence' > "$template/visible-artifact.mov"
  artifact_sha="$(sha256_file "$template/visible-artifact.mov")"
  artifact_bytes="$(wc -c < "$template/visible-artifact.mov" | tr -d '[:space:]')"
  procedure_sha="$(sha256_file "$PROCEDURE")"
  runner_sha="$(sha256_file "$T3_TOOL")"
  recipe_sha="$(recipe_sha256 "$RECIPE")"
  revision="${T3_TEST_HARNESS_REVISION:-$(git -C "$REPO_ROOT" rev-parse HEAD)}"

  cat > "$template/apply.log" <<'EOF'
{
  "version": 1,
  "generated_at": "2026-10-05T17:01:00Z",
  "mode": "apply",
  "apps": [{
    "id": "raycast",
    "entries": [{
      "bind": "profile.raycast.import",
      "kind": "generated_import",
      "confirm": "one_click",
      "actions": [
        {"op":"materialize","target":"fixture","result":"ok"},
        {"op":"deliver","target":"open fixture","result":"ok"}
      ],
      "drift": []
    }]
  }],
  "checklist": [{"app":"raycast","step":"Confirm import for Raycast","confirm":"one_click","satisfied":false}],
  "summary": {"writes":0,"adds":0,"dels":0,"files":0,"materialize":1,"drift":0,"manual":1},
  "exit_code": 3
}
EOF
  cat > "$template/idempotence.log" <<'EOF'
{
  "version": 1,
  "generated_at": "2026-10-05T17:02:00Z",
  "mode": "diff",
  "apps": [{
    "id": "raycast",
    "entries": [{
      "bind": "profile.raycast.import",
      "kind": "generated_import",
      "confirm": "one_click",
      "actions": [],
      "drift": []
    }]
  }],
  "checklist": [{"app":"raycast","step":"Confirm import for Raycast","confirm":"one_click","satisfied":false}],
  "summary": {"writes":0,"adds":0,"dels":0,"files":0,"materialize":0,"drift":0,"manual":1},
  "exit_code": 3
}
EOF
  : > "$template/apply.stderr.log"
  : > "$template/idempotence.stderr.log"
  cat > "$template/operator-observation.txt" <<'EOF'
procedure_id=raycast-generated-import
procedure_version=1
operator=synthetic-test-operator
observed_at=2026-10-05T17:03:00Z
challenge=ABC123
confirmation=PASS ABC123
accepted=true
observation=Synthetic test observation; this is not visual evidence.
EOF
  apply_sha="$(sha256_file "$template/apply.log")"
  apply_bytes="$(wc -c < "$template/apply.log" | tr -d '[:space:]')"
  apply_stderr_sha="$(sha256_file "$template/apply.stderr.log")"
  apply_stderr_bytes="$(wc -c < "$template/apply.stderr.log" | tr -d '[:space:]')"
  idempotence_sha="$(sha256_file "$template/idempotence.log")"
  idempotence_bytes="$(wc -c < "$template/idempotence.log" | tr -d '[:space:]')"
  idempotence_stderr_sha="$(sha256_file "$template/idempotence.stderr.log")"
  idempotence_stderr_bytes="$(wc -c < "$template/idempotence.stderr.log" | tr -d '[:space:]')"
  report_sha="$(sha256_file "$template/operator-observation.txt")"
  report_bytes="$(wc -c < "$template/operator-observation.txt" | tr -d '[:space:]')"

  jq -n \
    --arg procedure_sha "$procedure_sha" \
    --arg runner_sha "$runner_sha" \
    --arg recipe_sha "$recipe_sha" \
    --arg revision "$revision" \
    --arg artifact_sha "$artifact_sha" \
    --argjson artifact_bytes "$artifact_bytes" \
    --arg apply_sha "$apply_sha" \
    --argjson apply_bytes "$apply_bytes" \
    --arg apply_stderr_sha "$apply_stderr_sha" \
    --argjson apply_stderr_bytes "$apply_stderr_bytes" \
    --arg idempotence_sha "$idempotence_sha" \
    --argjson idempotence_bytes "$idempotence_bytes" \
    --arg idempotence_stderr_sha "$idempotence_stderr_sha" \
    --argjson idempotence_stderr_bytes "$idempotence_stderr_bytes" \
    --arg report_sha "$report_sha" \
    --argjson report_bytes "$report_bytes" \
    '{
      "$schema":"https://raw.githubusercontent.com/lucamaraschi/nix-me/main/packages/app-state/evidence/t3-run-record.schema.json",
      record_version:1,
      origin:"interactive-t3-runner",
      procedure:{
        id:"raycast-generated-import",
        version:1,
        path:"packages/app-state/evidence/procedures/raycast-generated-import.v1.json",
        sha256:$procedure_sha,
        harness_revision:$revision,
        runner_sha256:$runner_sha
      },
      recipe:{id:"raycast", path:"packages/app-state/recipes/raycast.yaml", sha256:$recipe_sha},
      environment:{kind:"disposable_vm", identifier:"synthetic-vm", macos:{version:"15.6", build:"24G84"}, architecture:"arm64"},
      application:{bundle_id:"com.raycast.macos", version:"1.100.0", build:"100000"},
      engine:{path:"/synthetic/nix-me-apps", version:"nix-me-apps synthetic"},
      run:{id:"placeholder", started_at:"2026-10-05T17:00:00Z", finished_at:"2026-10-05T17:04:00Z"},
      commands:{
        apply:{mode:"apply", output:"apply.log", output_sha256:$apply_sha, output_bytes:$apply_bytes, stderr:"apply.stderr.log", stderr_sha256:$apply_stderr_sha, stderr_bytes:$apply_stderr_bytes, exit_code:3, started_at:"2026-10-05T17:00:30Z", finished_at:"2026-10-05T17:01:00Z"},
        idempotence:{mode:"diff", output:"idempotence.log", output_sha256:$idempotence_sha, output_bytes:$idempotence_bytes, stderr:"idempotence.stderr.log", stderr_sha256:$idempotence_stderr_sha, stderr_bytes:$idempotence_stderr_bytes, exit_code:3, started_at:"2026-10-05T17:01:30Z", finished_at:"2026-10-05T17:02:00Z"}
      },
      operator:{
        attested:true,
        identity:"synthetic-test-operator",
        observed_at:"2026-10-05T17:03:00Z",
        challenge:"ABC123",
        confirmation:"PASS ABC123",
        observation:"Synthetic test observation; this is not visual evidence.",
        report:"operator-observation.txt",
        report_sha256:$report_sha,
        report_bytes:$report_bytes,
        artifact:{path:"visible-artifact.mov", media_type:"video/quicktime", sha256:$artifact_sha, bytes:$artifact_bytes}
      }
    }' > "$template/run-record.json"
}

make_case() {
  local suffix="$1"
  local run_dir="$RUNS_DIR/synthetic-t3-$$-$suffix"
  mkdir -p "$run_dir"
  cp "$TMP/template/"* "$run_dir/"
  jq --arg id "$(basename "$run_dir")" '.run.id = $id' "$run_dir/run-record.json" > "$run_dir/run-record.next"
  mv "$run_dir/run-record.next" "$run_dir/run-record.json"
  printf '%s\n' "$run_dir"
}

assert_failed_draft() {
  local run_dir="$1"
  local failed_check="$2"
  local draft="$run_dir/draft-manifest.json"

  "$T3_TOOL" collect-draft "$run_dir" >/dev/null
  [ "$(jq -r '.lifecycle' "$draft")" = "draft" ] || fail "collector did not emit a draft"
  [ "$(jq -r '.result.status' "$draft")" = "failed" ] || fail "incomplete run produced passing evidence"
  [ "$(jq -r --arg check "$failed_check" '.result.checks[$check].status' "$draft")" = "failed" ] \
    || fail "$failed_check was not marked failed"
  expect_failure 'lifecycle must be final' "$EVIDENCE_TOOL" generate-stamp "$draft" "$RECIPE"
  expect_failure 'run checks did not pass' \
    "$T3_TOOL" finalize "$run_dir" "$EVIDENCE_DIR/manifests/raycast.json"
}

mkdir -p "$RUNS_DIR"
if [ ! -d "$EVIDENCE_DIR/manifests" ]; then
  mkdir "$EVIDENCE_DIR/manifests"
  CREATED_MANIFESTS_DIR=true
fi
make_template
"$T3_TOOL" validate >/dev/null

valid_run="$(make_case valid)"
"$T3_TOOL" collect-draft "$valid_run" >/dev/null
[ "$(jq -r '.result.status' "$valid_run/draft-manifest.json")" = "passed" ] \
  || fail "complete synthetic run did not produce a passing draft"
expect_failure 'lifecycle must be final' \
  "$EVIDENCE_TOOL" generate-stamp "$valid_run/draft-manifest.json" "$RECIPE"
if [ ! -e "$EVIDENCE_DIR/manifests/raycast.json" ] && git -C "$REPO_ROOT" cat-file -e \
    "$(jq -r '.procedure.harness_revision' "$valid_run/run-record.json"):packages/app-state/evidence/tools/t3-procedure" \
    2>/dev/null; then
  "$T3_TOOL" finalize "$valid_run" "$EVIDENCE_DIR/manifests/raycast.json" >/dev/null
  CREATED_FINAL_MANIFEST=true
  [ "$(jq -r '.lifecycle' "$EVIDENCE_DIR/manifests/raycast.json")" = "final" ] \
    || fail "finalizer did not emit final lifecycle"
  [ "$(jq -r '.result.status' "$EVIDENCE_DIR/manifests/raycast.json")" = "passed" ] \
    || fail "finalizer did not preserve successful checks"
  "$EVIDENCE_TOOL" generate-stamp "$EVIDENCE_DIR/manifests/raycast.json" "$RECIPE" >/dev/null
  rm "$EVIDENCE_DIR/manifests/raycast.json"
  CREATED_FINAL_MANIFEST=false
fi

missing_operator="$(make_case missing-operator)"
jq '.operator.attested = false | .operator.confirmation = "FAIL"' \
  "$missing_operator/run-record.json" > "$missing_operator/run-record.next"
mv "$missing_operator/run-record.next" "$missing_operator/run-record.json"
assert_failed_draft "$missing_operator" visible_behavior

missing_visual="$(make_case missing-visual-artifact)"
rm "$missing_visual/visible-artifact.mov"
assert_failed_draft "$missing_visual" visible_behavior

missing_apply="$(make_case missing-apply-artifact)"
rm "$missing_apply/apply.log"
assert_failed_draft "$missing_apply" apply

failed_apply="$(make_case failed-apply)"
jq '.commands.apply.exit_code = 5' "$failed_apply/run-record.json" > "$failed_apply/run-record.next"
mv "$failed_apply/run-record.next" "$failed_apply/run-record.json"
jq '.exit_code = 5 | .apps[0].entries[0].actions[0].result = "failed"' \
  "$failed_apply/apply.log" > "$failed_apply/apply.next"
mv "$failed_apply/apply.next" "$failed_apply/apply.log"
assert_failed_draft "$failed_apply" apply

failed_idempotence="$(make_case failed-idempotence)"
jq '.apps[0].entries[0].actions = [{"op":"materialize","target":"fixture"}] | .exit_code = 2' \
  "$failed_idempotence/idempotence.log" > "$failed_idempotence/idempotence.next"
mv "$failed_idempotence/idempotence.next" "$failed_idempotence/idempotence.log"
jq '.commands.idempotence.exit_code = 2' \
  "$failed_idempotence/run-record.json" > "$failed_idempotence/run-record.next"
mv "$failed_idempotence/run-record.next" "$failed_idempotence/run-record.json"
assert_failed_draft "$failed_idempotence" idempotence

printf 'T3 procedure trust-boundary tests passed.\n'
