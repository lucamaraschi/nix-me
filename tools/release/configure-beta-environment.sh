#!/bin/bash

set -euo pipefail

REPOSITORY="${GITHUB_REPOSITORY:-lucamaraschi/nix-me}"
ENVIRONMENT="${NIX_ME_RELEASE_ENVIRONMENT:-macos-beta-release}"
TAG_PATTERN="${NIX_ME_RELEASE_TAG_PATTERN:-v*-*}"

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI is required" >&2
  exit 69
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "Authenticate GitHub CLI with 'gh auth login'" >&2
  exit 77
fi

echo "Configuring $ENVIRONMENT in $REPOSITORY..."
gh api \
  --method PUT \
  -H "Accept: application/vnd.github+json" \
  "repos/$REPOSITORY/environments/$ENVIRONMENT" \
  --input - >/dev/null <<'JSON'
{
  "wait_timer": 0,
  "prevent_self_review": false,
  "reviewers": [],
  "deployment_branch_policy": {
    "protected_branches": false,
    "custom_branch_policies": true
  }
}
JSON

policy_id="$(gh api \
  -H "Accept: application/vnd.github+json" \
  "repos/$REPOSITORY/environments/$ENVIRONMENT/deployment-branch-policies" \
  --jq ".branch_policies[] | select(.name == \"$TAG_PATTERN\" and .type == \"tag\") | .id" \
  | head -1)"

if [[ -z "$policy_id" ]]; then
  gh api \
    --method POST \
    -H "Accept: application/vnd.github+json" \
    "repos/$REPOSITORY/environments/$ENVIRONMENT/deployment-branch-policies" \
    -f name="$TAG_PATTERN" \
    -f type=tag >/dev/null
fi

echo "$ENVIRONMENT accepts release tags matching $TAG_PATTERN"
"$(dirname "$0")/check-macos-release-readiness.sh" "$ENVIRONMENT"
