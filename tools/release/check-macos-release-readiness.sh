#!/bin/bash

set -euo pipefail

REPOSITORY="${GITHUB_REPOSITORY:-lucamaraschi/nix-me}"
ENVIRONMENT="${1:-macos-beta-release}"
required_secrets=(
  CERTIFICATE_P12_BASE64
  CERTIFICATE_PASSWORD
  APPLE_API_KEY_ID
  APPLE_API_ISSUER_ID
  APPLE_API_PRIVATE_KEY_BASE64
  SPARKLE_PRIVATE_KEY
)

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI is required" >&2
  exit 69
fi

configured="$(gh secret list \
  --repo "$REPOSITORY" \
  --env "$ENVIRONMENT" \
  --json name \
  --jq '.[].name')"

missing=0
for secret in "${required_secrets[@]}"; do
  if grep -qx "$secret" <<<"$configured"; then
    printf 'ready   %s\n' "$secret"
  else
    printf 'missing %s\n' "$secret"
    missing=1
  fi
done

if ((missing != 0)); then
  echo "$ENVIRONMENT is not ready for a signed and notarized release" >&2
  exit 1
fi

echo "$ENVIRONMENT is ready for signed and notarized releases"
