{ config, lib, pkgs, ... }:

{
  programs.fish = {
    enable = true;
    
    interactiveShellInit = ''
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
    '';
    
    plugins = [
      # Z for directory jumping
      {
        name = "z";
        src = pkgs.fetchFromGitHub {
          owner = "jethrokuan";
          repo = "z";
          rev = "e0e1b9dfdba362f8ab1ae8c1afc7ccf62b89f7eb";
          sha256 = "0dbnir6jbwjpjalz14snzd3cgdysgcs3raznsijd6savad3qhijc";
        };
      }
      # Fish colored man pages
      {
        name = "fish-colored-man";
        src = pkgs.fetchFromGitHub {
          owner = "decors";
          repo = "fish-colored-man";
          rev = "1ad8fff696d48dcd8a683277e025ec2dfc1fe21f";
          sha256 = "0yc3xf9smqshj7cc94h8nai0gihs8g8qj95nqfify2jy7kgr0dkm";
        };
      }
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
    };
  };
  
  # Install additional tools that complement fish
  home.packages = with pkgs; [
    bat       # Better cat
    exa       # Better ls
    fd        # Better find
    ripgrep   # Better grep
    starship  # Customizable prompt
  ];
}