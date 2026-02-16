# Learnings - nix-me

## Project Structure
- Nix flake-based macOS configuration using nix-darwin + home-manager
- Modules split into `darwin/` (system-level) and `home-manager/` (user-level)
- Profile system in `hosts/profiles/` for work/personal/dev configurations

## Key Patterns
- `environment.etc` creates files in `/etc/` (e.g., `/etc/paths.d/nix`)
- Home-manager `home.file` creates files in `~/.config/` or `~/`
- Use `lib.mkDefault` for settings that can be overridden by profiles

## Package Hierarchy
- **Single source of truth**: `modules/darwin/apps/installations.nix` owns ALL packages
- **core.nix**: System config only (nix settings, paths.d, activation scripts) - NO packages
- **Profiles**: Customize via `systemPackagesToAdd`/`systemPackagesToRemove`
- **Avoid**: Defining `environment.systemPackages` in multiple modules (causes override conflicts)

## Makefile
- `make switch` prompts for Homebrew updates before darwin-rebuild
- Uses `brew outdated --verbose` to show current → new versions
- Non-blocking prompt with `read -r` - default is No

## Solutions
- **GUI apps can't find Nix binaries**: Add `/etc/paths.d/nix` with Nix paths via `environment.etc."paths.d/nix"`
- **Claude Code global settings**: Managed via home-manager in `modules/home-manager/apps/claude-code.nix`
