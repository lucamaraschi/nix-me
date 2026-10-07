#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVIDENCE_DIR="$(cd "$TEST_DIR/.." && pwd)"
REPO_ROOT="$(cd "$EVIDENCE_DIR/../../.." && pwd)"
TOOL="$EVIDENCE_DIR/tools/evidence-tool"
PASSED="$EVIDENCE_DIR/fixtures/valid/passed.json"
FAILED="$EVIDENCE_DIR/fixtures/valid/failed.json"
RECIPE="$EVIDENCE_DIR/fixtures/recipes/sample-app.yaml"
FIXTURE_KEY_SOURCE="$EVIDENCE_DIR/fixtures/trust/fixture-signing-key"
SIGNATURE_NAMESPACE="nix-me-t3-evidence-v1"
TMP="$(mktemp -d "$EVIDENCE_DIR/fixtures/.tests.XXXXXX")"
TEST_KEY="$TMP/fixture-signing-key"
PRODUCTION_MANIFEST="$EVIDENCE_DIR/manifests/rectangle.json"

cleanup() {
  if [ -f "$TMP/original-sample-app.yaml" ]; then
    cp "$TMP/original-sample-app.yaml" "$RECIPE"
  fi
  rm -f "$PRODUCTION_MANIFEST" "$PRODUCTION_MANIFEST.sig"
  rmdir "$EVIDENCE_DIR/manifests" 2>/dev/null || true
  rm -rf "$TMP"
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

sha256_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  else
    shasum -a 256 | awk '{print $1}'
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
  ' "$1" | sha256_stdin
}

sign_fixture() {
  local manifest="$1"

  rm -f "$manifest.sig"
  ssh-keygen -Y sign \
    -f "$TEST_KEY" \
    -n "$SIGNATURE_NAMESPACE" \
    "$manifest" >/dev/null 2>&1
}

cp "$FIXTURE_KEY_SOURCE" "$TEST_KEY"
chmod 600 "$TEST_KEY"

jq empty "$EVIDENCE_DIR/t3-evidence-manifest.schema.json"
"$TOOL" validate-manifest "$PASSED" >/dev/null
"$TOOL" validate-manifest "$FAILED" >/dev/null
jq '.lifecycle = "draft"' "$PASSED" > "$TMP/draft.json"
"$TOOL" validate-manifest "$TMP/draft.json" >/dev/null
expect_failure 'lifecycle must be final' \
  "$TOOL" generate-stamp "$TMP/draft.json" "$RECIPE"

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

cp "$PASSED" "$TMP/passed.json"
sign_fixture "$TMP/passed.json"
"$TOOL" generate-stamp "$TMP/passed.json" "$RECIPE" > "$TMP/stamp-1.json"
"$TOOL" generate-stamp "$TMP/passed.json" "$RECIPE" > "$TMP/stamp-2.json"
cmp "$TMP/stamp-1.json" "$TMP/stamp-2.json"
cmp "$TMP/stamp-1.json" "$EVIDENCE_DIR/fixtures/expected/sample-app.stamp.json"

sed 's/name: Synthetic T3 Fixture/name: Stale T3 Fixture/' "$RECIPE" > "$TMP/stale.yaml"
expect_failure 'recipe evidence is stale' \
  "$TOOL" generate-stamp "$TMP/passed.json" "$TMP/stale.yaml"

jq '.result.summary = "Hand-authored passing claim."' \
  "$PASSED" > "$TMP/hand-edited-passed.json"
expect_failure 'hand-edited-passed.json.sig' \
  "$TOOL" generate-stamp "$TMP/hand-edited-passed.json" "$RECIPE"

ssh-keygen -q -t ed25519 -N '' -C 'untrusted fixture signer' -f "$TMP/wrong-key"
cp "$PASSED" "$TMP/wrong-signer.json"
ssh-keygen -Y sign -f "$TMP/wrong-key" -n "$SIGNATURE_NAMESPACE" \
  "$TMP/wrong-signer.json" >/dev/null 2>&1
expect_failure 'signature signer is not explicitly allowed' \
  "$TOOL" generate-stamp "$TMP/wrong-signer.json" "$RECIPE"

cp "$PASSED" "$TMP/changed-after-signing.json"
sign_fixture "$TMP/changed-after-signing.json"
jq '.result.summary = "Changed after signing."' "$TMP/changed-after-signing.json" \
  > "$TMP/changed-after-signing.next"
mv "$TMP/changed-after-signing.next" "$TMP/changed-after-signing.json"
expect_failure 'invalid detached SSH signature' \
  "$TOOL" generate-stamp "$TMP/changed-after-signing.json" "$RECIPE"

jq '.procedure.harness_revision = "0000000000000000000000000000000000000000"' \
  "$PASSED" > "$TMP/nonexistent-revision.json"
sign_fixture "$TMP/nonexistent-revision.json"
expect_failure 'harness_revision does not resolve' \
  "$TOOL" generate-stamp "$TMP/nonexistent-revision.json" "$RECIPE"

mkdir -p "$EVIDENCE_DIR/manifests"
[ ! -e "$PRODUCTION_MANIFEST" ] || fail "test production manifest already exists"
jq \
  --arg sha256 "$(recipe_sha256 "$REPO_ROOT/packages/app-state/recipes/rectangle.yaml")" \
  '.recipe = {
    id: "rectangle",
    path: "packages/app-state/recipes/rectangle.yaml",
    sha256: $sha256
  }' \
  "$PASSED" > "$PRODUCTION_MANIFEST"
sign_fixture "$PRODUCTION_MANIFEST"
expect_failure 'fixture signers cannot authorize production evidence' \
  "$TOOL" generate-stamp \
    "$PRODUCTION_MANIFEST" "$REPO_ROOT/packages/app-state/recipes/rectangle.yaml"
expect_failure 'fixture signers cannot authorize production evidence' \
  "$TOOL" verify-repository
rm -f "$PRODUCTION_MANIFEST" "$PRODUCTION_MANIFEST.sig"
rmdir "$EVIDENCE_DIR/manifests" 2>/dev/null || true

cp "$RECIPE" "$TMP/original-sample-app.yaml"
sed '/^verified: null$/c\
verified:\
  macos: "15.6 (24G84)"\
  app: "1.2.3 (123)"\
  date: "2026-10-05"\
  harness: "hand-authored"' "$RECIPE" > "$TMP/sample-app.yaml"
cp "$TMP/sample-app.yaml" "$RECIPE"
expect_failure 'not the canonical stamp derived' \
  "$TOOL" verify-stamp "$TMP/passed.json" "$RECIPE"
cp "$TMP/original-sample-app.yaml" "$RECIPE"

"$TOOL" stamp-recipe "$TMP/passed.json" "$RECIPE" >/dev/null
"$TOOL" verify-stamp "$TMP/passed.json" "$RECIPE" >/dev/null
cp "$TMP/original-sample-app.yaml" "$RECIPE"
rm -f "$TMP/original-sample-app.yaml"
"$TOOL" verify-repository >/dev/null

jq '.artifacts[0].sha256 = "0000000000000000000000000000000000000000000000000000000000000000"' \
  "$PASSED" > "$TMP/tampered.json"
expect_failure "artifact 'run-record' SHA-256 mismatch" \
  "$TOOL" validate-manifest "$TMP/tampered.json"

printf 'Evidence tooling tests passed.\n'
# The procedure suite predates signed production manifests. Its synthetic
# revision override skips only the now-invalid unsigned production stamp path;
# signed final-manifest coverage above exercises the authenticated path.
T3_TEST_HARNESS_REVISION=0000000000000000000000000000000000000000 \
  "$REPO_ROOT/tests/vm/test-t3-procedures.sh"
