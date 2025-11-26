# VS Code Configuration for nix-me

This directory contains VS Code workspace settings to ensure proper integration with Nix.

## Files

### `settings.json`

Configures VS Code to find Nix binaries and work properly with Nix files.

**Key settings:**
- **PATH configuration**: Adds Nix directories to PATH so extensions can find `nix-instantiate`, `nixpkgs-fmt`, etc.
- **Nix IDE integration**: Enables the Nix language server for better editing experience
- **Format on save**: Automatically formats Nix files with nixpkgs-fmt

### `extensions.json`

Recommends helpful extensions for working with this project.

**Recommended extensions:**
- **Nix IDE** (`jnoortheen.nix-ide`): Syntax highlighting, formatting, and language server support

## Fixing "spawn nix-instantiate ENOENT" Error

If you see this error when saving Nix files, it means VS Code can't find the Nix binaries.

**Solutions:**

### 1. Reload VS Code Window (Quickest)

1. Open Command Palette: `Cmd+Shift+P`
2. Run: `Developer: Reload Window`
3. The new settings will be loaded

### 2. Restart VS Code from Terminal

Close VS Code and launch it from a terminal with Nix in PATH:

```bash
cd /Users/batman/src/lm/nix-me
code .
```

### 3. Install Nix IDE Extension

If you haven't installed it yet:

1. Open Extensions: `Cmd+Shift+X`
2. Search for "Nix IDE"
3. Install `jnoortheen.nix-ide`
4. Reload window

### 4. Verify Configuration

Check that the PATH is set correctly:

1. Open integrated terminal in VS Code: `Ctrl+` `
2. Run: `which nix-instantiate`
3. Should show: `/nix/var/nix/profiles/default/bin/nix-instantiate`

## Language Server

The configuration uses `nil` as the Nix language server.

**On Fresh Install:**
- `nil` is automatically installed via `modules/darwin/apps/installations.nix`
- VS Code is configured to use the absolute path: `/run/current-system/sw/bin/nil`
- No additional configuration needed - it just works!

**Path Configuration:**
- Uses absolute path to avoid PATH issues
- `/run/current-system/sw/bin/` is where nix-darwin places system packages
- Works immediately after `make switch` without VS Code restart

## Formatting

Nix files are automatically formatted on save using `nixpkgs-fmt` (already installed in base configuration).

To manually format:
- `Shift+Alt+F` (Format Document)
- Or save the file (auto-formats)

## GitHub Pull Requests Extension

### "Access Denied" Error

If you get an "access denied" error from the GitHub Pull Requests extension:

**Solution 1: Re-authenticate in VS Code**

1. Open Command Palette: `Cmd+Shift+P`
2. Type: `GitHub: Sign Out`
3. Sign out if prompted
4. Then type: `GitHub: Sign In`
5. Choose "Sign in with GitHub"
6. Complete authentication in browser
7. Authorize "Visual Studio Code" application

**Solution 2: Use GitHub CLI Authentication**

The GitHub CLI (`gh`) is already authenticated on your system. To use it with VS Code:

1. Make sure you're logged in: `gh auth status`
2. VS Code should automatically detect and use `gh` credentials
3. If not, try: `gh auth refresh -s repo,workflow,read:org`

**Solution 3: Check Token Scopes**

The extension needs these scopes:
- `repo` (full control of private repositories)
- `read:org` (read organization data)
- `workflow` (update GitHub Actions workflows)

To refresh with correct scopes:
```bash
gh auth refresh -s repo,workflow,read:org,gist
```

**Solution 4: SSH Configuration**

The project uses SSH for Git operations. Ensure:

1. SSH keys are added to GitHub account
2. If using 1Password SSH agent, it's configured correctly
3. Test SSH: `ssh -T git@github.com`

See `modules/home-manager/ssh.nix` for SSH configuration.

## Troubleshooting

### Extension still can't find nix-instantiate

Try setting the absolute path in your **User Settings** (not workspace):

1. Open Settings: `Cmd+,`
2. Search for "terminal.integrated.env.osx"
3. Edit in `settings.json`
4. Add:

```json
{
  "terminal.integrated.env.osx": {
    "PATH": "/nix/var/nix/profiles/default/bin:${env:HOME}/.nix-profile/bin:/etc/profiles/per-user/${env:USER}/bin:/run/current-system/sw/bin:${env:PATH}"
  }
}
```

### Still having issues?

1. Check that Nix is installed: `nix --version`
2. Check PATH in terminal: `echo $PATH | tr ':' '\n'`
3. Verify nix-instantiate exists: `ls -la /nix/var/nix/profiles/default/bin/nix-instantiate`
4. Restart VS Code completely (quit and reopen)

## Additional Tips

- Use the integrated terminal in VS Code for Nix commands
- Install recommended extensions when prompted
- Format Nix files to maintain consistency
- Use the language server for autocomplete and error checking
