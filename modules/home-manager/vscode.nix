# modules/home-manager/vscode.nix
{ config, lib, pkgs, ... }:

{
  programs.vscode = {
    enable = true;
    
    userSettings = {
      # Editor settings
      "editor.fontSize" = 14;
      "editor.fontFamily" = "JetBrainsMono Nerd Font, Menlo, Monaco, monospace";
      "editor.fontLigatures" = true;
      "editor.tabSize" = 2;
      "editor.insertSpaces" = true;
      "editor.rulers" = [ 80 120 ];
      "editor.formatOnSave" = true;
      "editor.renderWhitespace" = "boundary";
      "editor.minimap.enabled" = false;
      "editor.cursorBlinking" = "solid";
      "editor.smoothScrolling" = true;
      "editor.cursorSmoothCaretAnimation" = "on";
      
      # Workbench settings
      "workbench.startupEditor" = "none";
      "workbench.editor.enablePreview" = false;
      "workbench.colorTheme" = "Default Dark+ High Contrast";
      "workbench.iconTheme" = "material-icon-theme";
      "workbench.editor.tabSizing" = "shrink";
      
      # Terminal settings
      "terminal.integrated.fontSize" = 13;
      "terminal.integrated.fontFamily" = "JetBrainsMono Nerd Font Mono";
      "terminal.integrated.shell.osx" = "${pkgs.fish}/bin/fish";
      
      # File settings
      "files.trimTrailingWhitespace" = true;
      "files.insertFinalNewline" = true;
      "files.autoSave" = "onFocusChange";
      "files.exclude" = {
        "**/.git" = true;
        "**/.DS_Store" = true;
        "**/.direnv" = true;
        "**/node_modules" = true;
      };
      
      # Language-specific settings
      "[javascript]" = {
        "editor.defaultFormatter" = "esbenp.prettier-vscode";
      };
      "[typescript]" = {
        "editor.defaultFormatter" = "esbenp.prettier-vscode";
      };
      "[json]" = {
        "editor.defaultFormatter" = "esbenp.prettier-vscode";
      };
      "[markdown]" = {
        "editor.wordWrap" = "on";
        "editor.defaultFormatter" = "esbenp.prettier-vscode";
      };
      "[nix]" = {
        "editor.tabSize" = 2;
        "editor.formatOnSave" = true;
      };
      
      # Git settings
      "git.enableSmartCommit" = true;
      "git.confirmSync" = false;
      "git.autofetch" = true;
      
      # Explorer settings
      "explorer.compactFolders" = false;
    };
    
    keybindings = [
      {
        key = "cmd+1";
        command = "workbench.action.openEditorAtIndex1";
      }
      {
        key = "cmd+2";
        command = "workbench.action.openEditorAtIndex2";
      }
      {
        key = "cmd+3";
        command = "workbench.action.openEditorAtIndex3";
      }
      {
        key = "cmd+k cmd+i";
        command = "editor.action.formatDocument";
      }
      {
        key = "alt+cmd+l";
        command = "editor.action.formatDocument";
      }
      {
        key = "cmd+k cmd+t";
        command = "workbench.action.selectTheme";
      }
      {
        key = "ctrl+`";
        command = "workbench.action.terminal.toggleTerminal";
      }
    ];
    
    extensions = with pkgs.vscode-extensions; [
      # Theme and UI
      github.github-vscode-theme
      pkief.material-icon-theme
      
      # Language support
      ms-python.python
      rust-lang.rust-analyzer
      golang.go
      hashicorp.terraform
      jnoortheen.nix-ide
      
      # Git
      eamodio.gitlens
      
      # Editing enhancements
      esbenp.prettier-vscode
      formulahendry.auto-rename-tag
      
      # AI assistance
      github.copilot
      
      # Misc
      yzhang.markdown-all-in-one
      ms-azuretools.vscode-docker
    ] ++ pkgs.vscode-utils.extensionsFromVscodeMarketplace [
      # Additional extensions not in nixpkgs
      {
        name = "vscode-fish";
        publisher = "bmalehorn";
        version = "1.0.16";
        sha256 = "sha256-9Lxk9N9QGjZgDQgV5tB+2HXCDWLwTNOUUHbX4UkUGbM=";
      }
      {
        name = "remote-ssh";
        publisher = "ms-vscode-remote";
        version = "0.65.7";
        sha256 = "sha256-4bkErL3+PpZprpE1kBYQjbzRuUGlJJR1wfqFcG5iKMQ=";
      }
    ];
  };
}