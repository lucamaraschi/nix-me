# macOS distribution

Nix Me is distributed outside the Mac App Store. GitHub Releases is the source
of truth, Sparkle handles in-app updates, and a Homebrew tap provides a second
installation path.

## Release artifacts

Each stable release contains:

- `Nix-Me-VERSION.dmg`: universal, Developer ID signed, notarized, and stapled.
- `Nix-Me-VERSION.dmg.sha256`: download checksum.
- `appcast.xml`: Sparkle update feed signed with EdDSA.
- `nix-me.rb`: generated Homebrew cask for auditing and tap publication.

The in-app feed uses:

```text
https://github.com/lucamaraschi/nix-me/releases/latest/download/appcast.xml
```

## Required GitHub secrets

Configure these in the `lucamaraschi/nix-me` repository:

| Secret | Content |
| --- | --- |
| `CERTIFICATE_P12_BASE64` | Base64-encoded Developer ID Application certificate and private key exported as `.p12`. |
| `CERTIFICATE_PASSWORD` | Password used when exporting the `.p12`. |
| `APPLE_API_KEY_ID` | App Store Connect API key ID. |
| `APPLE_API_ISSUER_ID` | App Store Connect API issuer ID. |
| `APPLE_API_PRIVATE_KEY_BASE64` | Base64-encoded `AuthKey_*.p8` used by `notarytool`. |
| `SPARKLE_PRIVATE_KEY` | Private Sparkle key exported by `generate_keys`. Preserve it permanently. |
| `TAP_GITHUB_TOKEN` | Optional fine-grained token with write access to `lucamaraschi/homebrew-tap`. |

The committed Sparkle public key belongs to the Keychain account
`com.nix-me.manager`. Export its private key on this Mac without printing it:

```bash
macos/NixMeApp/.build/artifacts/sparkle/Sparkle/bin/generate_keys \
  --account com.nix-me.manager \
  -x /tmp/nix-me-sparkle-private-key
gh secret set SPARKLE_PRIVATE_KEY < /tmp/nix-me-sparkle-private-key
rm -f /tmp/nix-me-sparkle-private-key
```

Encode Apple credentials before adding them:

```bash
base64 < DeveloperIDApplication.p12 | gh secret set CERTIFICATE_P12_BASE64
base64 < AuthKey_KEYID.p8 | gh secret set APPLE_API_PRIVATE_KEY_BASE64
```

## Publishing

Merge release-ready changes to `main`, then create and push a semantic version
tag:

```bash
git tag -s v0.2.0 -m "Nix Me 0.2.0"
git push origin v0.2.0
```

The `Release macOS App` workflow tests the app, builds a universal bundle,
signs Sparkle from the inside out, creates and notarizes the DMG, generates the
signed appcast and cask, then publishes a GitHub Release. It updates the
Homebrew tap when `TAP_GITHUB_TOKEN` is configured.

The workflow can also be run manually for an existing tag.

## Local validation

Development builds stay ad-hoc signed:

```bash
make app-run
make app-package
```

To exercise a Developer ID build locally, set `CODE_SIGN_IDENTITY`,
`APP_VERSION`, `BUILD_NUMBER`, and optionally `NIX_ME_ARCHS` before running the
build and package scripts. Notarization additionally requires the App Store
Connect API variables accepted by `scripts/notarize-macos-app.sh`.
