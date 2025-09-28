{ config, lib, pkgs, ... }:

{
  programs.fish = {
    enable = true;

     # Create custom plugins using packageDir
    interactiveShellInit = ''
      # Load the plugins from plugin directories
      for plugin_dir in $__fish_config_dir/plugins/*
        if test -d $plugin_dir
          set -a fish_function_path $plugin_dir/functions
          set -a fish_complete_path $plugin_dir/completions
          for file in $plugin_dir/conf.d/*.fish
            if test -f $file
              source $file
            end
          end
        end
      end

      # Set up autopair key bindings (functions defined below in functions section)
      bind \042 '__autopair_insert \042 \042'
      bind \047 '__autopair_insert \047 \047'
      bind '(' '__autopair_insert ( )'
      bind '[' '__autopair_insert [ ]'
      bind '{' '__autopair_insert { }'
      bind \b __autopair_backspace

      # Colored man pages
      function man --wraps man
          set -l bold_ansi_code "\u001b[1m"
          set -l underline_ansi_code "\u001b[4m"
          set -l reversed_ansi_code "\u001b[7m"
          set -l reset_ansi_code "\u001b[0m"
          set -l teal_ansi_code "\u001b[36m"
          set -l green_ansi_code "\u001b[32m"
          set -l blue_ansi_code "\u001b[34m"
          set -l yellow_ansi_code "\u001b[33m"

          set -x LESS_TERMCAP_md (echo -e $bold_ansi_code$teal_ansi_code)
          set -x LESS_TERMCAP_me (echo -e $reset_ansi_code)
          set -x LESS_TERMCAP_us (echo -e $underline_ansi_code$green_ansi_code)
          set -x LESS_TERMCAP_ue (echo -e $reset_ansi_code)
          set -x LESS_TERMCAP_so (echo -e $reversed_ansi_code$blue_ansi_code)
          set -x LESS_TERMCAP_se (echo -e $reset_ansi_code)

          command man $argv
      end

      # Set fish greeting
      set fish_greeting ""

      # Set path
      fish_add_path ~/.local/bin
      fish_add_path ~/.npm-global/bin

      # Enable direnv if available
      if command -v direnv >/dev/null
        direnv hook fish | source
      end

      # Better colors
      set -g fish_color_normal normal
      set -g fish_color_command blue
      set -g fish_color_quote green
      set -g fish_color_redirection cyan
      set -g fish_color_end normal
      set -g fish_color_error red
      set -g fish_color_param normal
      set -g fish_color_comment brblack
      set -g fish_color_match --background=brblue
      set -g fish_color_selection --reverse
      set -g fish_color_search_match --background=brblack
      set -g fish_color_operator cyan
      set -g fish_color_escape magenta
      set -g fish_color_autosuggestion brblack

      # Use starship prompt if available
      if command -v starship >/dev/null
        starship init fish | source
      end

      # Custom functions
      function mkcd
        mkdir -p $argv && cd $argv
      end

      function trash
        command trash $argv
      end

      # Git shortcuts
      function gst
        git status
      end

      function gd
        git diff $argv
      end

      function gcm
        git commit -m $argv
      end

      function mknode
        mkdir -p $argv[1] && cd $argv[1]
        echo "use nix" > .envrc
        echo "{ pkgs ? import <nixpkgs> {} }: pkgs.mkShell { buildInputs = with pkgs; [ nodejs_22 nodePackages.pnpm ]; }" > shell.nix
        direnv allow
        echo "Node.js project ready in $(pwd)"
      end
    '';

    # Add functionality directly in home-manager instead of plugins
    plugins = [
    ];

    shellAliases = {
      ls = "ls --color=auto";
      ll = "ls -la";
      ".." = "cd ..";
      "..." = "cd ../..";
      g = "git";
      k = "kubectl";
      tf = "terraform";
      dc = "docker-compose";

      # System aliases
      update = "darwin-rebuild switch --flake ~/.config/nixpkgs";
      upgrade = "nix flake update ~/.config/nixpkgs && darwin-rebuild switch --flake ~/.config/nixpkgs";
    };

    functions = {
      __autopair_insert = {
        body = ''
          set -l open $argv[1]
          set -l close $argv[2]

          if commandline --paging-mode
              return
          end

          set -l buffer (commandline)
          set -l cursor (commandline --cursor)

          commandline --insert -- $open

          if test -n "$close"
              commandline --insert -- $close
              commandline --cursor (math $cursor + 1)
          end
        '';
      };

      __autopair_backspace = {
        body = ''
          set -l buffer (commandline)
          set -l cursor (commandline --cursor)

          if test $cursor -gt 0
              set -l prev_char (string sub --start=$cursor --length=1 $buffer)
              set -l next_char (string sub --start=(math $cursor + 1) --length=1 $buffer)

              # Remove matching pairs using octal escapes
              if test "$prev_char$next_char" = "()" -o "$prev_char$next_char" = "[]" -o "$prev_char$next_char" = "{}" -o "$prev_char$next_char" = \042\042 -o "$prev_char$next_char" = \047\047
                  commandline --cursor (math $cursor - 1)
                  commandline --delete --length=2
              else
                  commandline --delete --length=1
              end
          end
        '';
      };

      fish_prompt = {
        body = ''
          set -l last_status $status

          set -l normal (set_color normal)
          set -l usercolor (set_color green)
          set -l dircolor (set_color blue)
          set -l git_color (set_color magenta)

          # Show exit status of previous command if not successful
          if test $last_status -ne 0
            printf (set_color red)"[$last_status] "
          end

          # Username and hostname
          printf "$usercolor$USER@"(hostname | cut -d . -f 1)" "

          # Current directory, truncated if too long
          printf "$dircolor"(prompt_pwd)" "

          # Git status
          if command -v git >/dev/null
            set -l git_branch (git branch 2>/dev/null | grep '^*' | sed 's/* //')
            if test -n "$git_branch"
              printf "$git_color($git_branch) "
            end
          end

          # Prompt character
          printf "$normal❯ "
        '';
      };

      mknode = {
        body = ''
          set project_name $argv[1]

          if test -z "$project_name"
            echo "Usage: mknode <project-name>"
            return 1
          end

          mkdir -p $project_name
          cd $project_name

          # Create shell.nix
          cat > shell.nix << 'EOF'
          { pkgs ? import <nixpkgs> {} }:

          pkgs.mkShell {
            buildInputs = with pkgs; [
              nodejs_22
              nodePackages.pnpm
              nodePackages.typescript
              nodePackages.ts-node
              nodePackages.nodemon
            ];

            shellHook = '''
              echo "🚀 Node.js development environment loaded!"
              echo "Node: $(node --version)"
              echo "pnpm: $(pnpm --version)"

              # Auto-create package.json if it doesn't exist
              if [ ! -f package.json ]; then
                echo "Creating package.json..."
                pnpm init
              fi
            ''';
          }
          EOF

          # Create .envrc
          echo "use nix" > .envrc

          # Allow direnv
          direnv allow

          echo "✅ Node.js project '$project_name' created and ready!"
        '';
      };

      nixify = {
        body = ''
          # For existing projects - adds Nix support
          if test -f package.json
            echo "📦 Adding Nix support to existing Node.js project..."

            # Detect Node version from package.json or .nvmrc
            set node_version "nodejs_22"
            if test -f .nvmrc
              set detected_version (cat .nvmrc | string replace "v" "" | string replace "." "_")
              set node_version "nodejs_$detected_version"
              echo "Detected Node version from .nvmrc: $node_version"
            end

            cat > shell.nix << EOF
            { pkgs ? import <nixpkgs> {} }:

            pkgs.mkShell {
              buildInputs = with pkgs; [
                $node_version
                nodePackages.pnpm
                nodePackages.typescript
              ];
            }
            EOF

            echo "use nix" > .envrc
            direnv allow

            echo "✅ Nix support added! Environment ready."
          else
            echo "❌ No package.json found. Run this in a Node.js project directory."
            return 1
          end
        '';
      };
    };
  };

  # Create plugin directories manually
  home.file = {
  # Autopair functions are now defined inline in interactiveShellInit
  # Removed separate files to avoid loading issues

  # Your existing fzf configuration...
  ".config/fish/functions/fzf_configure_bindings.fish".text = ''
    function fzf_configure_bindings --description "Configure fzf key bindings"
        if command -v fzf >/dev/null
            bind \ct fzf-file-widget
            bind \cr fzf-history-widget
            bind \ec fzf-cd-widget
        end
    end
  '';

    ".config/fish/functions/fzf-file-widget.fish".text = ''
      function fzf-file-widget --description "Search files with fzf"
          set -l commandline (__fzf_parse_commandline)
          set -l dir $commandline[1]
          set -l fzf_query $commandline[2]

          set -l FZF_DEFAULT_OPTS "--height 40% --reverse $FZF_DEFAULT_OPTS $FZF_CTRL_T_OPTS"
          eval "find $dir -type f 2>/dev/null | fzf -m --query=\"$fzf_query\"" | while read -l result
              echo $result
          end
      end
    '';

    ".config/fish/functions/fzf-history-widget.fish".text = ''
      function fzf-history-widget --description "Search command history with fzf"
          history | fzf --height 40% --reverse --query=(commandline) | read -l result
          if test -n "$result"
              commandline -r "$result"
          end
          commandline -f repaint
      end
    '';

    ".config/fish/functions/fzf-cd-widget.fish".text = ''
      function fzf-cd-widget --description "Search directories with fzf"
          set -l FZF_DEFAULT_OPTS "--height 40% --reverse $FZF_DEFAULT_OPTS $FZF_ALT_C_OPTS"
          eval "find . -type d 2>/dev/null | fzf --query=(commandline)" | read -l result
          if test -n "$result"
              cd "$result"
              commandline -f repaint
          end
      end
    '';

    ".config/fish/functions/__fzf_parse_commandline.fish".text = ''
      function __fzf_parse_commandline --description "Parse current command line for fzf"
          set -l commandline (commandline)
          set -l dir "."
          set -l query ""

          if test -n "$commandline"
              set query "$commandline"
          end

          echo $dir
          echo $query
      end
    '';

    ".config/fish/conf.d/fzf.fish".text = ''
      # Initialize fzf key bindings
      if command -v fzf >/dev/null
          fzf_configure_bindings
      end
    '';
  };

  # Install additional tools that complement fish
  home.packages = with pkgs; [
    bat       # Better cat
    eza       # Better ls
    fd        # Better find
    fzf
    ripgrep   # Better grep
    starship  # Customizable prompt
  ];
}
