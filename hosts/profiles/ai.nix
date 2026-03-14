# AI/ML development and local LLM tools
# Run large language models locally on Apple Silicon
{ config, pkgs, lib, ... }:

{
  apps = {
    useBaseLists = true;

    # GUI Applications
    casksToAdd = [
      "lm-studio"           # MLX models, great Apple Silicon memory efficiency
      "docker"              # For Open WebUI container
    ];

    # CLI tools via Homebrew
    brewsToAdd = [
      "pi-coding-agent"     # Terminal AI coding agent (pi.dev)
    ];

    # Nix packages
    systemPackagesToAdd = [
      # "ollama"  # broken in nixpkgs - app/dist missing files in build
      "opencode"            # Terminal AI coding assistant (opencode.ai)
    ];
  };

  # AI/ML environment variables
  environment.variables = {
    OLLAMA_HOST = "127.0.0.1:11434";
    OLLAMA_MODELS = "$HOME/.ollama/models";
  };

  # ============================================================
  # POST-INSTALL SETUP
  # ============================================================
  # After running darwin-rebuild switch, run these commands:
  #
  # --- Ollama Setup ---
  # 1. Start Ollama service:
  #    ollama serve &
  #
  # 2. Pull recommended models:
  #    ollama pull deepseek-r1:7b      # Reasoning, math, code
  #    ollama pull llama3.2:3b         # General purpose, fast
  #    ollama pull qwen2.5-coder:7b    # Code generation
  #
  # 3. Test CLI:
  #    ollama run deepseek-r1:7b "Hello!"
  #
  # 4. Start Open WebUI (ChatGPT-like interface):
  #    docker run -d -p 3000:8080 \
  #      --add-host=host.docker.internal:host-gateway \
  #      -v open-webui:/app/backend/data \
  #      --name open-webui \
  #      --restart always \
  #      ghcr.io/open-webui/open-webui:main
  #
  # 5. Access Open WebUI at http://localhost:3000
  #
  # --- OpenCode Setup ---
  # 1. Login with your provider API key:
  #    opencode auth login
  #
  # 2. Run in any project directory:
  #    opencode
  #
  # --- Pi Coding Agent Setup ---
  # 1. Configure your API key:
  #    pi config
  #
  # 2. Run in any project directory:
  #    pi
  # ============================================================
}
