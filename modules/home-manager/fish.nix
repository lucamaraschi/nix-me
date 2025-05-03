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
          rev = "85f863f20f24faf675827fb00f3a4e15c7838d76"; # Current master commit
          sha256 = "sha256-+FUBM7CodtZrYKqU542fQD+ZDGrd2438trKM0tIESs0=";
        };
      }
      
      # Fish colored man pages
      {
        name = "fish-colored-man";
        src = pkgs.fetchFromGitHub {
          owner = "PatrickF1";
          repo = "colored_man_pages.fish";
          rev = "f335d2ab1d56667c3a2dce849354a05a39bf89c2"; # Current master commit
          sha256 = "sha256-fo5gJ0z9ZhMdJUQFMcOrlOdc+ATaHCf1qK7bdJli3xk=";
        };
      }
      
      # Auto-matching pairs - now using patrickf1's autopair
      {
        name = "autopair";
        src = pkgs.fetchFromGitHub {
          owner = "PatrickF1";
          repo = "autopair.fish";
          rev = "1222311994a0730e53d0708e185c53766e420461"; # Current master commit
          sha256 = "sha256-EAwT9TI2vlQ0X2t3/R96aq+CrGJNoCk7A95nrb/QxJY=";
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
    eza       # Better ls
    fd        # Better find
    ripgrep   # Better grep
    starship  # Customizable prompt
  ];
}