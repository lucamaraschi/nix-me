# Application adapter backlog

This backlog gives every application integration an explicit adapter decision. The
registry contains 58 recipes: 40 expose at least one machine-readable settings
surface and 18 remain intentionally manual or private. A recipe is not marked
verified until its allowlist and round trip have been checked against a recorded
application and macOS version, even when its adapter implementation is complete.
Evidence comes from the recipe registry and the local management snapshot. Selected
observed versions include Blender 5.1, Docker Desktop 4.38, OBS 32.0, VLC 3.0.21,
Xcode 26.6, and Zoom 7.1.9.

## Current progress

- **W0 is complete.** The engine now has allowlisted JSON-pointer projection and
  merge, INI/VLC/Wireshark key-value and FreeCAD QSettings codecs, strict version
  gates, typed command values, reviewed-source validation, redaction assertions,
  semantic read-back, and verified transactional rollback. Structured command
  arguments replace shell value interpolation, and file/path handling rejects
  traversal, symlinks, hard links, and ambiguous ownership. Atomic replacement
  never widens an existing mode and preserves macOS ACLs and extended attributes.
- **W1 is complete for the proven local surfaces.** Ghostty and Hammerspoon use
  reviewed-source export; FreeCAD, OBS, VLC, Wireshark, and Zenmap have typed,
  allowlisted file settings. Executable Hammerspoon Lua always requires explicit
  review and confirmation.
- **W2 is complete for the proven native interfaces.** Eleven CFPreferences-based
  recipes expose 52 typed settings. Docker Desktop exposes 26 safe settings; Orka,
  Spotify, Zoom, and Tailscale expose only the scalar settings demonstrated by their
  local stores or CLI. Blender remains manual because arbitrary Python execution is
  not an acceptable adapter boundary.
- **W3 is complete for evidenced pointer-only stores.** Figma, Miro, Notion,
  Proton Mail, and Slack expose narrowly allowlisted JSON pointers. GitHub Desktop
  and Linear contained only private, list, migration, or window-state material;
  Chrome requires a separate managed-policy adapter. Those recipes remain closed.
- **W4's engine primitive is complete but no app has been promoted.** The owned JXA
  Accessibility action format is typed, version-gated, exact-selector only, and
  rollback verified. Adobe Creative Cloud, Autodesk Fusion, Bambu Connect, Elgato
  Camera Hub, Loom, Teams, and Telegram stay manual until sanitized selector
  fixtures exist; the implementation does not invent UI selectors.
- **W5 is complete.** 1Password CLI and Codex CLI expose only ephemeral
  ready/not-ready status through the management API and the app's Private filter;
  command output and account details are never persisted or displayed.
- Generated imports are intentionally non-converged until a recipe can prove the
  resulting application state: successful launch dispatch is shown as requested,
  never as verified, and remains retryable on the next plan.
- The 18 intentionally manual/private recipes are Adobe Creative Cloud, Autodesk
  Fusion, Bambu Connect, Blender, Codex CLI, Elgato Camera Hub, GitHub Desktop,
  Google Chrome, Hopper Disassembler, Linear, LM Studio, Loom, Microsoft OneDrive,
  Microsoft OneNote, Microsoft Teams, 1Password CLI, 1Password, and Telegram.

## Adapter contract

AI may help discover schemas and generate fixtures, but runtime adapters must be
deterministic. Every adapter must:

1. Declare supported app and macOS version ranges and refuse unknown major versions.
2. Capture only an allowlist of ordinary portable preferences into typed harness
   values. Deny credentials, tokens, cookies, licenses, document history, cloud
   content, databases, caches, device identities, and machine-generated paths.
3. Produce a redacted preview before saving. Never copy an opaque directory or
   database because it happens to contain preferences.
4. Apply atomically where files are involved, use the least invasive supported API,
   and state whether the app must be stopped or restarted.
5. Verify by reading the same interface back and comparing normalized values. A
   process exit code or successful click is not verification.
6. Ship capture/apply fixtures, redaction tests, rollback tests, and at least one
   version-specific real-app check before replacing a manual recipe.

Permissions are opt-in and checked before planning. Full Disk Access (FDA) is only
acceptable for a reviewed container path; Accessibility (AX) is a last resort and
must never enter passwords, recovery codes, license keys, or authentication tokens.

## Delivery waves

- **W0 - adapter primitives:** add INI/QSettings and key-value codecs, Electron JSON
  allowlists, typed CFPreferences export, version predicates, redaction assertions,
  semantic read-back verification, and a version-gated AX action format.
- **W1 - reviewed local state:** convert stable source files and locally observed
  text formats. These provide broad value with the smallest privilege surface.
- **W2 - native interfaces:** implement CFPreferences and available CLI/API adapters.
- **W3 - application stores:** implement explicitly allowlisted Electron/JSON and
  container adapters; require close-before-write and schema fixtures.
- **W4 - UI fallback:** add AX adapters only where no stable file, defaults domain,
  CLI, managed-policy interface, or API exists.
- **W5 - private boundary:** retain manual authentication only, with a non-sensitive
  readiness marker. These items are intentionally not exporters.

## Parser/codec exporters

`Apply / verify` means parse and normalize, write atomically while the app is closed,
restart when required, then parse again and compare the allowlisted model.

| App | Portable preferences and adapter input | Apply / verify | Permissions and version risk | Permanently excluded | Wave |
| --- | --- | --- | --- | --- | --- |
| Docker Desktop | CPU, memory, disk limit, update and daemon feature settings from `~/Library/Group Containers/group.com.docker/settings-store.json` with `settings.json` fallback (both observed locally) | Patch documented keys; restart with `docker desktop restart`; re-read store and check engine status | FDA may be needed for the group container; Docker 4.x store names and keys vary, and the installed 4.38 CLI has no settings command | Registry credentials, contexts, Kubernetes data, extensions, VM disk and machine IDs | W2 |
| Figma | Launch, update, font-helper and UI preferences from `~/Library/Application Support/Figma/settings.json` and `desktop_state.json` (observed) | JSON deep-merge and read back after relaunch | Close Figma; Electron schema and helper version are coupled | Login, teams/files, cache, analytics IDs and font contents | W3 |
| FreeCAD | General, editor, workbench and path settings from the recipe path `~/Library/Application Support/FreeCAD/user.cfg` | QSettings/XML codec; preserve unknown groups; relaunch and compare typed keys | No extra permission; gate by FreeCAD major/minor because parameter names move | Recent files, document state and absolute project paths unless explicitly host-scoped | W1 |
| GitHub Desktop | Theme, update channel, editor/shell choice and confirmation preferences from observed `Preferences` and `window-state.json` | Electron JSON codec; relaunch and semantic read-back | Close app; key names can change with Electron/Desktop releases | OAuth, accounts, repository list/history, cookies and IndexedDB | W3 |
| Google Chrome | Allowlisted browser preferences from `Local State` and `<profile>/Preferences`; managed policy values should be preferred where supported | Patch only reviewed JSON paths or policy plist; launch and query `chrome://policy` through a test profile | Close all Chrome processes; schema is release/profile dependent; managed policies may override | Passwords, cookies, history, bookmarks, extensions, sync identity and profile content | W3 |
| Linear | Window, launch and notification presentation preferences from observed `~/Library/Application Support/Linear/Preferences` and `window-state.json` | Electron JSON codec and read-back after relaunch | Close app; Electron store changes frequently | Workspace data, OAuth/session tokens, IndexedDB and cached issue content | W3 |
| LM Studio *(not installed)* | Theme, runtime defaults, model directory and server preferences from its Electron preference files after a sanitized fixture is captured | JSON adapter; verify through file read-back and local server status where applicable | Discovery task must establish paths and version schema first | Downloaded models, chats, API tokens and model files | W3 |
| Miro | Launch, UI and notification presentation settings from the Electron `Preferences` file after local path/schema discovery | JSON codec; relaunch and read back | Close app; version-gate every observed schema | Credentials, teams, boards, cookies, IndexedDB and cache | W3 |
| Notion | Launch, appearance and window behavior from observed `Preferences` and `state.json` | Allowlisted JSON patch; relaunch and read back | Close app; state schema changes often | `notion.db`, bridge tokens, accounts, workspace content, cookies and cache | W3 |
| OBS Studio | General UI/output defaults from recipe-managed `global.ini` and observed `user.ini`; optionally sanitized scene metadata with a dedicated schema | INI codec; stop OBS, patch sections, restart, read back; run a headless config smoke check | Screen Recording remains a human TCC grant; plugins add unknown sections; gate by OBS major | Stream keys, service credentials, recording paths by default, browser cookies and secret-bearing profile/scene fields | W1 |
| Orka Desktop | Non-secret endpoint aliases, UI and launch preferences from observed `~/.config/orka-desktop/globalConfig.json` and `appConfig.json` | JSON codec; relaunch and read back; optional unauthenticated endpoint reachability check | No extra permission expected; schema tied to Orka Desktop release | Tokens, certificates, cluster authorization and local session | W2 |
| Proton Mail | Ordinary launch, appearance and notification presentation values from observed Electron `Preferences` only | Allowlisted JSON patch and read-back after relaunch | Treat the application-support directory as sensitive; fail closed on unknown keys | Account data, mail/cache databases, encryption material, cookies and sessions | W3 |
| Slack | Launch, locale, appearance and notification presentation values from observed `local-settings.json` and `Preferences` | Allowlisted JSON merge; relaunch and read back | Close app; workspace settings can be server-controlled; gate by Slack major schema | Workspace tokens, cookies, workspaces, messages, IndexedDB and `root-state.json` | W3 |
| Spotify | Launch and playback preferences from observed `~/Library/Application Support/Spotify/prefs` | Key-value codec preserving comments/unknown keys; relaunch and read back | Close app; undocumented keys may change between releases | Account, OAuth, DRM, offline media, cache and listening history | W2 |
| VLC | Interface, playback, audio, subtitle and update preferences from observed `~/Library/Preferences/org.videolan.vlc/vlcrc`; selected typed values may also exist in `org.videolan.vlc` | VLC key-value codec; relaunch and compare effective values | Gate by VLC major; avoid duplicate plist/vlcrc ownership | Recent media, resume positions, network credentials and media paths unless host-scoped | W1 |
| Wireshark | UI, capture display and protocol preferences from recipe path `~/.config/wireshark/preferences` | Wireshark key-value codec; relaunch and compare normalized keys | No special permission for preferences; capture privileges are separate; gate by Wireshark major | Recent captures, capture files, TLS keys, credentials and interface-specific secrets | W1 |
| Zenmap | UI, scan-profile and command defaults from recipe path `~/.zenmap/zenmap.conf` | INI codec; relaunch and read back | No extra permission; gate by Zenmap/Nmap major | Scan history, target history, output files and credentials | W1 |
| Zoom | Audio/video defaults, launch and meeting UI preferences from observed `us.zoom.xos` plus `~/Library/Application Support/zoom.us/data/viper.ini` | Typed plist plus INI codec under one adapter; relaunch and read back both stores | Camera/microphone grants stay human-controlled; Zoom changes keys frequently | Account/session, meeting history, contacts, chat databases, device IDs and tokens | W2 |

## Defaults/plist exporters

These adapters use CFPreferences or a reviewed plist allowlist, not raw `defaults`
file copying. Apply through CFPreferences, synchronize, perform the declared app
restart, and read the same domain back.

| App | Portable preferences and adapter input | Apply / verify | Permissions and version risk | Permanently excluded | Wave |
| --- | --- | --- | --- | --- | --- |
| 1Password | Appearance, menu-bar behavior, update preferences and other non-secret UI values from observed domain `com.1password.1password` | CFPreferences allowlist; relaunch and compare | Do not inspect application-support databases; security-policy keys require one-click confirmation; gate by major | Vaults, items, credentials, account metadata, device trust, biometrics and secret keys | W2 |
| Hopper Disassembler | Theme, disassembly UI, update and analysis-display preferences from `com.cryptic-apps.hopper-web-4` or its container domain after discovery | CFPreferences allowlist; relaunch and read back | License store must be proven separate; domain may change with Hopper major | License activation, recent documents and analyzed binaries | W2 |
| iA Writer | Editor typography, appearance, focus mode and UI preferences from `pro.writer.mac` | CFPreferences allowlist; relaunch and read back | Sandboxed/iCloud app; FDA must not be used to reach document containers; gate by app major | Documents, library locations by default, account and iCloud state | W2 |
| Microsoft Excel | Editing, calculation, view and proofing preferences from observed `com.microsoft.Excel` plus reviewed shared Office preference keys | CFPreferences allowlist; relaunch and read back | Office build and organization policy can override values; group-container reads may require FDA | Identity, license, add-ins, documents, recent files, macros and cloud policy state | W2 |
| Microsoft OneDrive | Launch, notification, bandwidth and Files On-Demand preferences from its domain/group-container preference plist after schema discovery | CFPreferences/plist allowlist; restart OneDrive and read back | Group container/File Provider access may require FDA; policy can override | Accounts, tokens, sync databases, synchronized roots, file-provider authorization and files | W2 |
| Microsoft OneNote | Editing, appearance and proofing preferences from the OneNote container preference domain after discovery | CFPreferences allowlist; relaunch and read back | Containerized domain and Office build changes; possible FDA for direct plist access | Accounts, notebooks, cache, sync state and identities | W2 |
| Microsoft Outlook | Appearance, editor, notification presentation and calendar UI preferences from observed `com.microsoft.Outlook` | CFPreferences allowlist; relaunch and read back | Organization policy/new-Outlook mode can change ownership; version-gate both modes | Accounts, mail databases, identities, credentials, signatures unless separately reviewed, and policy | W2 |
| Microsoft PowerPoint | Editing, view, slideshow and proofing preferences from observed `com.microsoft.Powerpoint` plus reviewed shared Office keys | CFPreferences allowlist; relaunch and read back | Office build/policy risk; group-container reads may require FDA | Identity, license, templates, add-ins, documents and recent files | W2 |
| Microsoft Word | Editing, view, save and proofing preferences from observed `com.microsoft.Word` plus reviewed shared Office keys | CFPreferences allowlist; relaunch and read back | Office build/policy risk; group-container reads may require FDA | Identity, license, templates, add-ins, documents, macros and recent files | W2 |
| OpenSCAD | Editor, rendering, view and library preferences from observed `org.openscad.OpenSCAD` keys such as `design.autoReload` | CFPreferences allowlist; relaunch and compare | Current local app is 2021.01; establish fixtures for current and newer Qt builds | Recent files and absolute library/project paths unless host-scoped | W1 |
| PDF Expert | Appearance, view, tab and annotation-tool defaults from observed `com.readdle.PDFExpert-Mac` container preferences | CFPreferences allowlist; relaunch and read back | Sandbox container may require FDA; gate by app major | Documents, cloud connections, credentials, recents and synchronization databases | W2 |
| Proton VPN | Launch, protocol and non-secret connection-behavior preferences from `ch.protonvpn.mac` | CFPreferences allowlist; relaunch and compare; verify network extension separately | VPN configuration approval remains manual; policy/key names may change | Credentials, server session, network-extension authorization and VPN identity | W2 |
| UTM | UI, update, console and library-display preferences from `com.utmapp.UTM`; use `utmctl` only for non-secret verification | CFPreferences apply; relaunch, read back, and run `utmctl` health check | Gate by UTM major; do not mutate VMs during app-preference apply | VM bundles, disks, saved state, shared-folder secrets and machine identifiers | W2 |
| VirtualBuddy | UI, update, library and virtualization defaults from observed `codes.rambo.VirtualBuddy` | CFPreferences allowlist; relaunch and read back | Keys are app-version specific; paths must be explicitly host-scoped | VM bundles, disk images, restore state and guest secrets | W2 |
| Xcode | Editor, navigation, completion and source-control UI preferences from `com.apple.dt.Xcode`; themes, snippets and keybindings require separately reviewed file schemas | CFPreferences apply plus atomic reviewed-file delivery; relaunch and semantic read-back | Gate by Xcode major; developer tools may migrate keys automatically | Apple accounts, signing identities/certificates, provisioning profiles, simulators, derived data and recent projects | W2 |

## CLI/API exporters

| App | Portable preferences and adapter input | Apply / verify | Permissions and version risk | Permanently excluded | Wave |
| --- | --- | --- | --- | --- | --- |
| Blender | Interface, editing, input, save/load and enabled-extension settings via Blender's Python preferences API; invoke the observed `/Applications/Blender.app/Contents/MacOS/Blender` | Run versioned Python in background mode, save user preferences, then query the same RNA properties in a fresh process | No extra permission; RNA names and extension APIs change by Blender major | Startup scene/content, recent files, credentials, downloaded extensions and arbitrary Python | W2 |
| Tailscale | `accept-routes`, DNS, shields-up, exit-node policy and update behavior through the CLI embedded in `/Applications/Tailscale.app` | Use idempotent CLI flags; verify with JSON status/preferences output without persisting identity fields | Network-extension approval and some changes require admin/user confirmation; gate by CLI capability detection | Node keys, tailnet identity, auth keys, device authorization and peer data | W2 |

## Version-gated macOS Accessibility automation

AX adapters are a fallback for ordinary settings only. Each script must assert the
bundle version, localization, window title, control role and current value before
acting; verify the resulting control value after relaunch. Any mismatch stops the
entire adapter without clicking.

| App | Portable preferences to automate | Apply / verify | Permissions and version risk | Permanently excluded | Wave |
| --- | --- | --- | --- | --- | --- |
| Adobe Creative Cloud *(not installed)* | Launch-at-login, update behavior, sync toggles and notification preferences | AX Settings navigation and control read-back | Accessibility; installation-path and localization variants require fixtures | Credentials, licenses, installed-app payloads, cloud libraries and files | W4 |
| Autodesk Fusion | UI layout, editor/navigation behavior, update and non-account workspace preferences | AX Preferences automation; reopen dialog and compare controls | Accessibility; current install is under `~/Applications`; UI changes and cloud policy are high risk | Login, license, cloud projects, sessions and project content | W4 |
| Bambu Connect | Non-secret UI, launch and notification preferences only | AX Settings automation and control read-back | Accessibility; printer-dependent controls and localization make the adapter fragile | Printer access codes, device identity, cloud account/session and job history | W4 |
| Elgato Camera Hub *(not installed)* | Launch behavior and portable UI defaults that are independent of a camera serial number | AX automation and control read-back using a no-device fixture first | Accessibility plus camera permission for real-device tests; hardware/firmware matrix is high risk | Device calibration, serial-bound settings, firmware state and camera permission | W4 |
| Loom | Launch, capture UI, quality defaults and notification preferences | AX Settings automation and control read-back | Accessibility; Screen Recording and microphone grants remain manual TCC actions; frequent Electron UI changes | Login, recordings, workspace, upload history and permissions database | W4 |
| Microsoft Teams | Appearance, launch, notification presentation and meeting-device defaults | AX Settings automation; reopen and compare controls | Accessibility, microphone/camera for device tests; server policy and rapid releases can override values | Tokens, tenant/account, chats, meetings, organizational policy and device authorization | W4 |
| Telegram | Appearance, download limits and notification presentation | AX Settings automation; reopen and read selected controls | Accessibility; localization and Telegram UI revisions are high risk | Encryption keys, sessions, chats, contacts, media and account identity | W4 |

## Reviewed source-file management

These files are already the applications' intended user-authored configuration.
They should be saved as reviewed source artifacts rather than converted to generic
key/value JSON. Capture is an explicit file diff; apply is atomic replacement with
syntax validation and rollback.

| App | Portable source and input | Apply / verify | Permissions and version risk | Permanently excluded | Wave |
| --- | --- | --- | --- | --- | --- |
| Ghostty | The recipe path `~/.config/ghostty/config` | Validate with Ghostty's config parser when available, replace atomically, restart, and check diagnostics | No extra permission; reject unsupported directives for the installed Ghostty version | Shell-expanded secrets and machine-only paths unless explicitly marked host-scoped | W1 |
| Hammerspoon | The recipe path `~/.hammerspoon/init.lua` | Run `luac -p` or Hammerspoon parse check, replace atomically, reload with `hs`, and require a successful sentinel callback | Accessibility is required for Hammerspoon behavior; arbitrary Lua is code and always requires reviewed-source confirmation | Inline credentials, tokens and machine-only paths; never execute source during capture | W1 |

## Permanently private state

These integrations have no independent portable setting surface: their ordinary
preferences are owned by another adapter, while their remaining state is
authentication material. Keep a manual step and expose only an ephemeral readiness
check; never write its output to harness values or logs.

| App | Allowed readiness input | Apply / verify | Permissions and version risk | Permanently excluded | Wave |
| --- | --- | --- | --- | --- | --- |
| 1Password CLI | In-memory exit status from an `op` account/session readiness check; desktop preferences belong to the 1Password adapter | Never authenticate automatically; report ready/not ready without account details | Requires 1Password desktop integration and user authorization; CLI behavior is version-gated | Accounts, emails, vaults, session tokens, credentials and device trust | W5 |
| Codex CLI | In-memory authentication-status exit code; portable CLI preferences remain owned by the existing Codex integration | Never perform login; report ready/not ready and delegate settings verification to the Codex adapter | Gate on CLI capability; no Accessibility permission | OAuth/API credentials, session data, conversation data and account identity | W5 |

## Definition of done

An app leaves the manual list only when its adapter has an allowlisted portable
schema, redaction fixtures containing representative secrets, capture/apply/rollback
tests, semantic read-back verification, and a verified stamp for at least one
supported app/macOS pair. Hybrid apps such as OBS may become partially exportable
while retaining an explicit private-state warning. W5 integrations remain visible
as intentional private boundaries rather than unfinished exporters.
