# Terminal and desktop AI coding agents
# Can be combined with dev.nix on machines used for software work
{ config, pkgs, lib, ... }:

{
  apps = {
    useBaseLists = true;

    # Agent applications distributed as Homebrew casks
    casksToAdd = [
      "claude-code"        # Claude Code CLI
      "claude"             # Claude Desktop
      "codex"              # OpenAI Codex CLI
      "codex-app"          # OpenAI Codex Desktop
    ];

    # Agent CLIs distributed as Homebrew formulae
    brewsToAdd = [
      "pi-coding-agent"    # Terminal AI coding agent (pi.dev)
    ];

    # Agent CLIs distributed through nixpkgs
    systemPackagesToAdd = [
      "opencode"           # Terminal AI coding assistant (opencode.ai)
    ];
  };

  # ============================================================
  # POST-INSTALL SETUP
  # ============================================================
  # OpenCode:
  #   opencode auth login
  #   opencode
  #
  # Pi Coding Agent:
  #   pi config
  #   pi
  # ============================================================
}
