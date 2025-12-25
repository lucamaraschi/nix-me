# modules/home-manager/apps/claude-code.nix
# Global Claude Code configuration
# These settings apply to all projects unless overridden by project-specific .claude/settings.json
{ config, lib, pkgs, ... }:

let
  # Global Claude Code settings
  claudeSettings = {
    # Don't add "Co-authored-by" to commits
    includeCoAuthoredBy = false;

    # Global permissions that apply everywhere
    # Project-specific permissions should be in .claude/settings.json per-repo
    permissions = {
      allow = [
        # Safe read-only commands
        "Bash(ls:*)"
        "Bash(cat:*)"
        "Bash(find:*)"
        "Bash(tree:*)"
        "Bash(wc:*)"
        "Bash(echo:*)"
        "Bash(printf:*)"

        # Git commands
        "Bash(git status:*)"
        "Bash(git diff:*)"
        "Bash(git log:*)"
        "Bash(git branch:*)"
        "Bash(git add:*)"
        "Bash(git commit:*)"
        "Bash(git push:*)"
        "Bash(git pull:*)"
        "Bash(git checkout:*)"
        "Bash(git rm:*)"

        # Nix commands
        "Bash(nix:*)"
        "Bash(nix-env:*)"
        "Bash(nix-instantiate:*)"
        "Bash(darwin-rebuild:*)"

        # Homebrew
        "Bash(brew:*)"
        "Bash(brew search:*)"
        "Bash(brew info:*)"

        # Development tools
        "Bash(npm:*)"
        "Bash(pnpm:*)"
        "Bash(npx:*)"
        "Bash(node:*)"
        "Bash(tsc:*)"

        # System tools
        "Bash(mkdir:*)"
        "Bash(chmod:*)"
        "Bash(mv:*)"
        "Bash(readlink:*)"

        # Web access
        "WebFetch(domain:github.com)"
        "WebSearch"
      ];
      deny = [];
    };
  };
in
{
  # Create ~/.claude/settings.json
  home.file.".claude/settings.json" = {
    text = builtins.toJSON claudeSettings;
  };
}
