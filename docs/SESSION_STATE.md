# nix-me - Session State

> This file captures the current state of the nix-me project for context continuity across machines and sessions. Update it after significant operations.

**Last updated:** 2026-02-08
**Branch:** main
**Latest commit:** 601420b - Fix TUI system info hook with absolute paths
**Working tree:** Clean

---

## Project Summary

nix-me is a declarative macOS configuration management system built on Nix (nix-darwin + home-manager). It abstracts Nix complexity behind an interactive CLI with wizards, fzf-powered browsing, and composable profiles. No Nix knowledge required.

**Stack:** Nix flakes, nix-darwin, home-manager, shell scripts (4,900+ lines), React/Ink TUI (minimal)

---

## Active Machines

| Machine | Hardware | User | Profiles | Notes |
|---------|----------|------|----------|-------|
| **nabucodonosor** | MacBook | batman | dev, work, personal, hacking, maker | All profiles; portable powerhouse |
| **bellerofonte** | MacBook Pro | batman | dev, work | Work-focused |
| **zion** | Mac Mini | batman | dev, work, personal, maker | Maker station; Ctrl/Cmd swap for PC keyboard |

---

## Known Issues

### HIGH: Process accumulation during multiple searches
- **File:** `lib/package-manager.sh` lines 156-170 (`browse_homebrew_casks_fzf`)
- **Problem:** fzf and `brew info` processes not cleaned up between searches
- **Symptoms:** Hangs, resource leaks, zombies on repeated search
- **Fix:** Add trap handlers, capture fzf PID, kill preview processes on exit
- **Details:** `docs/ISSUES_SUMMARY.txt`, `docs/SEARCH_IMPLEMENTATION_ANALYSIS.md`

### MEDIUM: Non-installed packages missing preview details
- **File:** `lib/package-manager.sh` lines 140-149, 162
- **Problem:** Inconsistent formatting breaks fzf `{2}` token extraction for non-installed packages
- **Fix:** Use consistent delimiter (pipe `|`) in output, update preview token
- **Details:** `docs/ISSUES_SUMMARY.txt`, `docs/CODE_REFERENCE_GUIDE.md`

---

## Recent Changes (last 20 commits)

```
601420b Fix TUI system info hook with absolute paths
ade5403 Fix TUI dashboard box rendering
6437b5b Fix color escape codes in CLI output
a19294d Fix Zion keyboard mapping persistence across reboots
4f24aeb Use defaults write instead of PlistBuddy for Spotlight shortcuts
7e61ff3 Fix Spotlight shortcut properly with full dict structure
e143579 Add Claude Desktop and Codex to dev profile
c12ef2b Swap Ctrl and Command keys on Zion
6ec2e7c Fix Raycast startup and Spotlight shortcut persistence
5514968 Updated Zion?
ced9534 Fixed nabucodonosor's apps
347d744 Update README: add hacking/maker profiles, Claude Code docs, /etc troubleshooting
d7dd60d Fixed Zion packages
bf7bce7 Auto-backup /etc files before darwin-rebuild
a839e3d Fix Rectangle: use macOS defaults and add launchd agent
c1370f2 Fix fish: add Nix paths early to ensure aliases work
7c55519 Fix maker profile: openscad is a cask, not formula
223e0bb Remove openscad from nabucodonosor (now in maker profile)
bdca3a4 Add maker profile with 3D printing and CAD tools
514a17a Feature/hacking profile (#13)
```

---

## Architecture Overview

```
nix-me/
├── bin/nix-me              # Main CLI (712 lines) - entry point for all commands
├── lib/                    # Shell libraries (4,189 lines)
│   ├── tui.sh              # TUI menu system (757 lines)
│   ├── vm-manager.sh       # UTM VM lifecycle (882 lines)
│   ├── diff-packages.sh    # Package diffing (619 lines)
│   ├── wizard.sh           # Profile selection (576 lines)
│   ├── package-manager.sh  # Package browsing with fzf (467 lines) ⚠️ has bugs
│   ├── config-wizard.sh    # Setup wizard (371 lines)
│   ├── config-builder.sh   # Config file generation (270 lines)
│   ├── create-utm-vm.sh    # UTM VM creation (187 lines)
│   └── ui.sh               # Shared UI helpers (60 lines)
├── modules/
│   ├── darwin/              # macOS system config (core, system, keyboard, display, shell, fonts)
│   │   └── apps/installations.nix  # Base package lists (brew formulas, casks, MAS apps)
│   ├── home-manager/        # User config (git, ssh, claude-code, fish, rectangle)
│   ├── nixos/               # NixOS support (fish)
│   └── shared/              # Cross-platform (fish-base)
├── hosts/
│   ├── types/               # Hardware templates (shared, macbook, macbook-pro, macmini, vm)
│   ├── profiles/            # Composable profiles (dev, work, personal, hacking, maker)
│   └── machines/            # Per-machine overrides (bellerofonte, nabucodonosor, zion, nixos-vm)
├── overlays/                # Nix overlays (nodejs 22.14, airjack)
├── tui/                     # React/Ink TUI (minimal - entry point + fallback)
├── flake.nix                # Main Nix config (289 lines, 15+ host definitions)
├── Makefile                 # Build system (make switch, build, update, check, clean)
└── install.sh               # One-line installer with wizard
```

---

## Key Commands

```bash
# Apply configuration
make switch                  # Build and activate (auto-backups /etc)
make build                   # Test build without applying

# CLI
./bin/nix-me browse          # fzf-powered package browser
./bin/nix-me search <query>  # Search packages
./bin/nix-me add app <name>  # Add GUI app
./bin/nix-me add tool <name> # Add CLI tool
./bin/nix-me list            # Show installed packages
./bin/nix-me status          # System overview
./bin/nix-me doctor          # Diagnostics (8 checks)
./bin/nix-me diff            # Preview changes
./bin/nix-me rollback        # Undo last change
./bin/nix-me vm              # VM management menu

# Nix
nix flake check              # Validate configuration
nix flake update             # Update inputs
```

---

## Profiles System

| Profile | GUI Apps | CLI Tools | Special |
|---------|----------|-----------|---------|
| **dev** | VS Code, Docker, OrbStack, UTM, Claude Code, Claude Desktop, Codex | fd, gcc, jq, Node.js, Python, Rust, Go | Xcode (MAS) |
| **work** | Teams, Slack, Zoom, MS Office, Linear | terraform, kubectl, helm, awscli2 | 5s screen lock |
| **personal** | Spotify, OBS, Steam, Figma, Notion | yt-dlp, ffmpeg, transmission-cli | 5min screen lock |
| **hacking** | Wireshark, Ghidra | Metasploit, nmap, hashcat, aircrack-ng | AirJack overlay |
| **maker** | Fusion 360, Blender, FreeCAD, OpenSCAD | (none extra) | Bambu Studio manual |

Profiles are composable and can add/remove packages from each other.

---

## Pending Tasks

- [ ] Fix process accumulation in `lib/package-manager.sh` (HIGH)
- [ ] Fix non-installed package preview in `lib/package-manager.sh` (MEDIUM)
- [x] ~~Expand React/Ink TUI beyond minimal stub~~ — Dashboard with system info, packages, quick actions
- [ ] Clean up unclear commit "Updated Zion?" (5514968)
- [ ] Investigate starship not loading on Zion (home-manager packages not in PATH?)
- [ ] Symlink `~/.config/nixpkgs` → `~/src/lm/nix-me` to avoid config sync issues

---

## Feature Ideas

### Project Manager
Implement functionality to clone, sync, and manage git repositories grouped by category (work, personal, etc.).

**Concept:**
- Define projects in nix config or separate YAML/Nix file
- Group by category: `work`, `personal`, `oss`, etc.
- Commands: `nix-me projects sync`, `nix-me projects clone <group>`, `nix-me projects status`
- Auto-clone missing repos on new machine setup
- Optionally auto-pull/fetch on schedule or manual trigger
- Store in standard locations like `~/src/work/`, `~/src/personal/`

**Example config:**
```nix
projects = {
  work = [
    { url = "git@github.com:company/repo1.git"; path = "~/src/work/repo1"; }
    { url = "git@github.com:company/repo2.git"; }
  ];
  personal = [
    { url = "git@github.com:user/dotfiles.git"; }
  ];
  oss = [
    { url = "git@github.com:nixos/nixpkgs.git"; shallow = true; }
  ];
};
```

---

## Key Files for Quick Context

| Need to understand... | Read these files |
|----------------------|-----------------|
| Full project overview | `README.md` |
| Nix configuration | `flake.nix` |
| Package lists | `modules/darwin/apps/installations.nix` |
| Machine overrides | `hosts/machines/*/default.nix` |
| Profile definitions | `hosts/profiles/*.nix` |
| CLI implementation | `bin/nix-me` |
| Known bugs | `docs/ISSUES_SUMMARY.txt` |
| Build system | `Makefile` |

---

## Notes

- The project uses `nix-darwin` (not plain NixOS) for macOS management
- Homebrew is managed declaratively through nix-darwin's `homebrew` module
- Mac App Store apps require being signed in to the App Store first
- `/etc` files are auto-backed up before `darwin-rebuild` to prevent activation errors
- Fish is the primary shell; Nix paths are added early to ensure aliases work
- 1Password SSH agent is integrated for key management
- Ctrl/Cmd keys are swapped on Zion for PC keyboard compatibility (via LaunchAgent for persistence)
- **Config sync:** Working in `~/src/lm/nix-me` but system uses `~/.config/nixpkgs`. Either symlink them or push/pull to sync changes.
- **TUI:** Uses React/Ink with manual border rendering (Ink's borderStyle has bugs). System info fetches use absolute paths.
