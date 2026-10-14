# H-031: first scored recipe batch

This batch uses the pre-batch ranking in
`packages/app-state/metrics/recipe-candidates.json` at base commit `d70dcf9`.
It delivers the first three candidates with a documented, local ownership
boundary and headless convergence coverage. Registration alone does not activate
a recipe: the engine requires a matching top-level app ID in an explicitly
supplied values file.

No deployable values were added under `packages/app-state/values`. That directory
is a values input in some read-only and operator-driven flows, so shipping example
values there would make activation intent ambiguous. The non-secret examples used
by the tests live at
`tools/app-state/tests/first-recipe-batch/fixtures/values.yaml` and are never a
system activation input.

## Queue decisions

| Candidate rank | Candidate | Decision | Rationale |
|---:|---|---|---|
| 1 | Docker Desktop | Skip | The signaled state combines daemon settings, contexts, credentials, Desktop databases, and a secrets engine. No narrow ownership boundary or headless app/daemon test is available without reverse-engineering unstable state. |
| 2 | Obsidian | Skip | Meaningful settings are scoped to user-selected vaults under `.obsidian`; the current recipe model has no explicit vault selection. The global Electron support directory also mixes sessions and cloud-owned state. |
| 3 | Google Chrome | Skip | Chrome profiles mix sync-owned preferences with cookies, tokens, extension state, and frequently rewritten databases. Managed policy is a separate surface, and the queue does not provide a safe local subset. |
| 4 | DBeaver Community Edition | Skip | The score is based only on a cask plist path. Connection definitions, credentials, and workspace state are separate, and no reviewed key allowlist exists without reverse-engineering. |
| 5 | LibreOffice | Skip | The profile tree mixes settings, extensions, macros, recovery data, and recent-document state. The cask signal does not identify a stable merge boundary that can be tested credibly. |
| 6 | Sublime Text | Deliver | The documented user preferences file is structured JSONC and can be deep-merged. |
| 7 | iTerm2 | Deliver | Official dynamic profiles provide a dedicated, immediately reloaded JSON plist that avoids the global and private preference domains. |
| 8 | Maccy | Deliver | The open-source app declares stable typed `UserDefaults` keys; a small allowlist avoids clipboard data and privacy policy state. |

## Sublime Text

- **Owned state:** only keys supplied under `sublime-text.preferences`, merged into `Packages/User/Preferences.sublime-settings`.
- **Preserved/unowned:** unlisted preference keys, keymaps, projects, syntax-specific settings, installed packages, caches, sessions, and license state. JSONC comments and formatting are not semantic state and may be normalized on write.
- **Secret exclusions:** package credentials, license material, repository tokens, and session data are not represented by the recipe or example values.
- **Apply/poke:** Sublime Text watches its settings files, so apply performs an atomic deep merge and uses `poke: none`.
- **Manual residue:** first adoption of an existing unmanaged preference file is reported as out-of-band drift and requires reviewed `--force`; package installation, sign-in, and settings outside this file remain manual.

## iTerm2

- **Owned state:** the complete `Profiles` value supplied under `iterm2.dynamic_profiles` in the dedicated `DynamicProfiles/nix-me.json` file; unknown top-level keys in that file are preserved.
- **Preserved/unowned:** regular profiles, the default-profile choice, global preferences, private preferences, shell integration, history, and every other dynamic-profile file.
- **Secret exclusions:** profile commands must not embed passwords, tokens, private keys, or secret environment values. None are present in the test example.
- **Apply/poke:** iTerm2 monitors the DynamicProfiles directory and reloads valid plist files immediately, so `poke: none` is sufficient.
- **Manual residue:** first adoption of an existing `nix-me.json` is reported as out-of-band drift and requires reviewed `--force`; selecting the dynamic profile or making it the default remains an explicit user choice.

## Maccy

- **Owned state:** only `historySize`, `pasteByDefault`, `removeFormattingByDefault`, `showFooter`, and `showInStatusBar` when explicitly supplied under `maccy.defaults`.
- **Preserved/unowned:** all other defaults, keyboard shortcuts, launch-at-login state, updater state, ignored-app/type privacy lists, pinned items, window geometry, clipboard history, and the system clipboard.
- **Secret exclusions:** clipboard contents and the app/type ignore lists can reveal sensitive activity and are deliberately excluded.
- **Apply/poke:** typed CFPreferences writes are synchronized, then Maccy is restarted. `unsafe_to_kill: true` forces confirmation even with `--yes`; declining leaves both preferences and the running app unchanged.
- **Manual residue:** Accessibility approval, launch-at-login changes, shortcut capture, and clipboard/history migration remain manual.

All three recipes remain `verified: null`; headless tests are T0/T1 evidence, not
production T3 evidence.

## Sources

- Sublime Text settings: <https://www.sublimetext.com/docs/settings.html>
- iTerm2 dynamic profiles: <https://iterm2.com/documentation-dynamic-profiles.html>
- Maccy defaults declarations reviewed at commit `19c3d8282f50316779085964b5148b76d4bb88ce`: <https://github.com/p0deje/Maccy/blob/19c3d8282f50316779085964b5148b76d4bb88ce/Maccy/Extensions/Defaults.Keys%2BNames.swift>

## Verification

```sh
cd packages/app-state/engine
cargo run -p nix-me-apps -- registry validate --recipe ../recipes --json
cargo run -p nix-me-apps -- registry catalog-validate --catalog ../catalog/homebrew-top-200-apps.json --recipe ../recipes --json

cd ../../..
cargo test --manifest-path tools/app-state/tests/first-recipe-batch/Cargo.toml
python3 tools/app-state/score_recipe_candidates.py --check
python3 -m unittest discover -s tools/app-state -p 'test_*.py'
```
