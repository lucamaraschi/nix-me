# macOS distribution

Nix Me is distributed outside the Mac App Store. GitHub Releases is the source
of truth, Sparkle handles in-app updates, and a Homebrew tap provides a second
installation path.

## Managed-host installation

Machines controlled by this repository build and install the app through Nix
instead of downloading a release. The manager is enabled by default. A host
can explicitly opt out with:

```nix
apps.manager.enable = false;
```

The `nix-me-macos` package builds only from the native app and management API
sources, bundles the matching `nix-me-apps` engine, and ad-hoc signs the final
application after Nix fixups. Activation copies the signed bundle to
an installation staging directory, signs it with the user's existing certificate
when available, then moves it to `/Applications/Nix Me.app`. It records its Nix source under `/var/db/nix-me` and
registers it with Launch Services. Nix reuses the store result until one of
those inputs changes and reinstalls the matching app when the system generation
is switched or rolled back.

Sparkle is intentionally excluded from managed-host builds because updates are
delivered by the Nix configuration. These local builds are suitable for trusted
managed Macs and do not replace Developer ID signing and notarization for
downloadable GitHub releases.

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

## Protected release environments

Prerelease jobs use the `macos-beta-release` GitHub environment. Its deployment
policy accepts tags matching `v*-*`, so ordinary branches and stable tags cannot
read its credentials. Stable jobs use the separate `macos-stable-release`
environment; its approval policy is tracked as `AUT-007` in `PLAN.md`.

Create or repair the beta environment with:

```bash
tools/release/configure-beta-environment.sh
```

Configure these as **environment secrets**, not repository secrets:

| Secret | Content |
| --- | --- |
| `CERTIFICATE_P12_BASE64` | Base64-encoded Developer ID Application certificate and private key exported as `.p12`. |
| `CERTIFICATE_PASSWORD` | Password used when exporting the `.p12`. |
| `APPLE_API_KEY_ID` | App Store Connect API key ID. |
| `APPLE_API_ISSUER_ID` | App Store Connect API issuer ID. |
| `APPLE_API_PRIVATE_KEY_BASE64` | Base64-encoded `AuthKey_*.p8` used by `notarytool`. |
| `SPARKLE_PRIVATE_KEY` | Private Sparkle key exported by `generate_keys`. Preserve it permanently. |
| `TAP_GITHUB_TOKEN` | Optional fine-grained token with write access to `lucamaraschi/homebrew-tap`. |

`TAP_GITHUB_TOKEN` is only used for stable releases. Check beta readiness
without exposing secret values:

```bash
tools/release/check-macos-release-readiness.sh macos-beta-release
```

The committed Sparkle public key belongs to the Keychain account
`com.nix-me.manager`. Export its private key on this Mac without printing it:

```bash
apps/macos/NixMeApp/.build/artifacts/sparkle/Sparkle/bin/generate_keys \
  --account com.nix-me.manager \
  -x /tmp/nix-me-sparkle-private-key
gh secret set SPARKLE_PRIVATE_KEY \
  --env macos-beta-release \
  --repo lucamaraschi/nix-me \
  < /tmp/nix-me-sparkle-private-key
rm -f /tmp/nix-me-sparkle-private-key
```

Encode Apple credentials before adding them:

```bash
base64 < DeveloperIDApplication.p12 \
  | gh secret set CERTIFICATE_P12_BASE64 --env macos-beta-release
base64 < AuthKey_KEYID.p8 \
  | gh secret set APPLE_API_PRIVATE_KEY_BASE64 --env macos-beta-release
gh secret set CERTIFICATE_PASSWORD --env macos-beta-release
gh secret set APPLE_API_KEY_ID --env macos-beta-release
gh secret set APPLE_API_ISSUER_ID --env macos-beta-release
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

The workflow can also be run manually for an existing tag. Select that tag as
the workflow ref; dispatching from a branch is intentionally rejected by the
environment deployment policy.

## Local validation

Development builds automatically reuse a certificate identity when available:

```bash
make app-run
make app-package
```

To exercise a Developer ID build locally, set `CODE_SIGN_IDENTITY`,
`APP_VERSION`, `BUILD_NUMBER`, and optionally `NIX_ME_ARCHS` before running the
build and package scripts. Notarization additionally requires the App Store
Connect API variables accepted by `tools/release/notarize-macos-app.sh`.

## Stable signing and privacy approvals

`tools/release/sign-macos-app.sh` signs the app, bundled app-state engine, and
Sparkle's nested executables. It selects an existing Developer ID Application
identity, or Apple Development for local builds, in deterministic fingerprint
order. After successful signing and verification it stores only the public
certificate fingerprint in
`~/Library/Application Support/Nix Me/signing-identity` (mode 0600).
Subsequent builds reuse that pin even if another certificate is added. A missing
or expired pinned certificate fails with recovery instructions; it never silently
switches identities or downgrades to ad-hoc signing.

Select or deliberately rotate a certificate with:

```bash
CODE_SIGN_IDENTITY="CERTIFICATE_SHA1_FINGERPRINT" make app
```

`CODE_SIGN_IDENTITY=-` explicitly requests ad-hoc signing, for example in CI.
`NIX_ME_REQUIRE_STABLE_SIGNING=1` refuses ad-hoc fallback.
`NIX_ME_SIGNING_TIMESTAMP=none` permits offline local signing; release builds
use secure timestamps. `NIX_ME_SIGNING_IDENTITY_FILE` overrides the local pin
location for isolated builds/tests. Neither certificates nor private keys should
be stored in Git or the Nix store.

Nix builds remain reproducible and ad-hoc signed inside the build sandbox.
Activation signs the staged application as the target user, outside that sandbox,
using the same pin and the user's Keychain. The login Keychain must be unlocked;
macOS may ask to allow codesign to use the selected private key. Signing failures
leave the previously installed app untouched. Optional host controls:

```nix
apps.manager.signingIdentity = "auto"; # or an explicit certificate fingerprint
apps.manager.requireStableSigning = true;
```

On a new Mac with no signing certificate, the default remains a working ad-hoc
local build with a prominent warning. It cannot promise persistent privacy
approvals across rebuilds. No certificate is minted, no trust settings are
changed, and no private key is transferred automatically. End users who do not
have signing credentials should use a consistently Developer ID-signed release;
Apple Development is for local testing, not general distribution.

The Resolve Access guide inspects the running signature and exposes that warning
when appropriate. Stable signing helps macOS recognize app updates, but does not
grant Full Disk Access, bypass app-container protections, or replace explicit user
approval. Notarization is a separate distribution check, not a privacy grant.
