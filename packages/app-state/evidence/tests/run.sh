#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVIDENCE_DIR="$(cd "$TEST_DIR/.." && pwd)"
REPO_ROOT="$(cd "$EVIDENCE_DIR/../../.." && pwd)"
TOOL="$EVIDENCE_DIR/tools/evidence-tool"
PASSED="$EVIDENCE_DIR/fixtures/valid/passed.json"
FAILED="$EVIDENCE_DIR/fixtures/valid/failed.json"
RECIPE="$EVIDENCE_DIR/fixtures/recipes/sample-app.yaml"
TMP="$(mktemp -d "$EVIDENCE_DIR/.tests.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

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

jq empty "$EVIDENCE_DIR/t3-evidence-manifest.schema.json"
"$TOOL" validate-manifest "$PASSED" >/dev/null
"$TOOL" validate-manifest "$FAILED" >/dev/null

expect_failure '$.environment: is required' \
  "$TOOL" validate-manifest "$EVIDENCE_DIR/fixtures/invalid/missing-environment.json"
expect_failure '$.artifacts[0].sha256: is required' \
  "$TOOL" validate-manifest "$EVIDENCE_DIR/fixtures/invalid/missing-artifact-metadata.json"
jq 'del(.procedure)' "$PASSED" > "$TMP/missing-procedure.json"
expect_failure '$.procedure: is required' \
  "$TOOL" validate-manifest "$TMP/missing-procedure.json"
jq 'del(.result)' "$PASSED" > "$TMP/missing-result.json"
expect_failure '$.result: is required' \
  "$TOOL" validate-manifest "$TMP/missing-result.json"
expect_failure 'result.status must be passed' \
  "$TOOL" generate-stamp "$FAILED" "$RECIPE"

"$TOOL" generate-stamp "$PASSED" "$RECIPE" > "$TMP/stamp-1.json"
"$TOOL" generate-stamp "$PASSED" "$RECIPE" > "$TMP/stamp-2.json"
cmp "$TMP/stamp-1.json" "$TMP/stamp-2.json"
cmp "$TMP/stamp-1.json" "$EVIDENCE_DIR/fixtures/expected/sample-app.stamp.json"

cp "$RECIPE" "$TMP/sample-app.yaml"
TMP_RECIPE_PATH="${TMP#"$REPO_ROOT/"}/sample-app.yaml"
jq --arg path "$TMP_RECIPE_PATH" '.recipe.path = $path' "$PASSED" > "$TMP/passed.json"
sed 's/name: Synthetic T3 Fixture/name: Stale T3 Fixture/' "$RECIPE" > "$TMP/stale.yaml"
expect_failure 'recipe evidence is stale' \
  "$TOOL" generate-stamp "$TMP/passed.json" "$TMP/stale.yaml"

sed '/^verified: null$/c\
verified:\
  macos: "15.6 (24G84)"\
  app: "1.2.3 (123)"\
  date: "2026-10-05"\
  harness: "hand-authored"' "$RECIPE" > "$TMP/sample-app.yaml"
expect_failure 'not the canonical stamp derived' \
  "$TOOL" verify-stamp "$TMP/passed.json" "$TMP/sample-app.yaml"

"$TOOL" stamp-recipe "$TMP/passed.json" "$TMP/sample-app.yaml" >/dev/null
"$TOOL" verify-stamp "$TMP/passed.json" "$TMP/sample-app.yaml" >/dev/null
"$TOOL" verify-repository >/dev/null

jq '.artifacts[0].sha256 = "0000000000000000000000000000000000000000000000000000000000000000"' \
  "$PASSED" > "$TMP/tampered.json"
expect_failure "artifact 'apply-log' SHA-256 mismatch" \
  "$TOOL" validate-manifest "$TMP/tampered.json"

printf 'Evidence tooling tests passed.\n'
