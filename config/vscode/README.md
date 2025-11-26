# VS Code Configuration for nix-me

This directory contains VS Code workspace configuration that is automatically installed to `.vscode/` by the `install.sh` script.

## What's Configured

### Nix Language Support
- **Nix IDE** extension for syntax highlighting and language features
- **nil** language server for code completion and diagnostics
- **nixpkgs-fmt** for automatic formatting on save

### PATH Configuration
Ensures VS Code can find Nix binaries by adding these paths:
- `/nix/var/nix/profiles/default/bin` - System Nix packages
- `~/.nix-profile/bin` - User Nix packages
- `/etc/profiles/per-user/$USER/bin` - Per-user profile
- `/run/current-system/sw/bin` - nix-darwin system packages
- `/opt/homebrew/bin` - Homebrew packages

### GitHub Integration
- Configured to use SSH protocol for GitHub operations
- GitHub Pull Requests extension recommended

## Installation

The installer automatically copies these files to `.vscode/`:
```bash
./install.sh
```

Or manually:
```bash
cp -r config/vscode/ .vscode/
```

## Troubleshooting

### "spawn nix-instantiate ENOENT"
This error means VS Code can't find the `nix-instantiate` binary. Solutions:
1. Restart VS Code after running `install.sh`
2. Ensure `nil` language server is installed: `nix-env -iA nixpkgs.nil`
3. Check PATH in VS Code: Terminal → New Terminal, then run `echo $PATH`

### "Command nil not found"
The Nix language server is not installed. Run:
```bash
make switch
```

This will install `nil` via the nix-me configuration.

### GitHub Authentication
If you get "access denied" with GitHub Pull Requests extension:
1. Open Command Palette (Cmd+Shift+P)
2. Type "GitHub: Sign out"
3. Type "GitHub: Sign in"
4. Choose "Sign in with GitHub (SSH)"

## Files

- **settings.json** - Workspace settings (PATH, formatters, language servers)
- **extensions.json** - Recommended VS Code extensions
- **README.md** - This file
