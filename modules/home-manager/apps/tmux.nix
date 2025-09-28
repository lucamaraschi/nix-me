# modules/home-manager/tmux.nix
{ config, lib, pkgs, username, ... }:

{
  programs.tmux = {
    enable = true;
    
    # Use Fish as default shell
    shell = "${pkgs.fish}/bin/fish";
    
    # Basic settings
    baseIndex = 1;                 # Start window numbering at 1
    escapeTime = 0;                # No delay for escape key press
    historyLimit = 50000;          # Scrollback buffer size
    keyMode = "vi";                # Use vi keys
    terminal = "tmux-256color";    # Full color support
    mouse = true;                  # Enable mouse support
    clock24 = true;                # Use 24-hour clock
    
    # Use C-a as prefix instead of C-b
    shortcut = "a";
    
    # Plugins
    plugins = with pkgs.tmuxPlugins; [
      sensible       # Sensible defaults
      pain-control   # Better pane management
      yank           # Better copy/paste
      resurrect      # Session saving & restoring
      continuum      # Automatic session saving
      {
        plugin = dracula;
        extraConfig = ''
          set -g @dracula-show-battery false
          set -g @dracula-show-powerline true
          set -g @dracula-refresh-rate 10
          set -g @dracula-show-left-icon session
          set -g @dracula-border-contrast true
          set -g @dracula-show-flags true
          set -g @dracula-show-weather false
        '';
      }
      {
        plugin = resurrect;
        extraConfig = "set -g @resurrect-strategy-nvim 'session'";
      }
      {
        plugin = continuum;
        extraConfig = ''
          set -g @continuum-restore 'on'
          set -g @continuum-save-interval '10'
        '';
      }
    ];
    
    # Extra configuration
    extraConfig = ''
      # Status bar design
      set -g status-position top
      
      # Enable full color support
      set -g default-terminal "tmux-256color"
      set -ga terminal-overrides ",*256col*:Tc"
      set -as terminal-overrides ',*:Smulx=\E[4::%p1%dm'  # undercurl support
      set -as terminal-overrides ',*:Setulc=\E[58::2::%p1%{65536}%/%d::%p1%{256}%/%{255}%&%d::%p1%{255}%&%d%;m'  # underscore colors

      # Enable focus events
      set -g focus-events on
      
      # Automatically renumber windows when one is closed
      set -g renumber-windows on
      
      # Activity monitoring
      set -g monitor-activity on
      set -g visual-activity off
      
      # Pane border styling
      set -g pane-border-style fg=colour238
      set -g pane-active-border-style fg=colour51
      
      # Window styling
      setw -g window-status-current-style fg=colour81,bg=colour238,bold
      setw -g window-status-current-format ' #I#[fg=colour250]:#[fg=colour255]#W#[fg=colour50]#F '
      setw -g window-status-style fg=colour138,bg=colour235,none
      setw -g window-status-format ' #I#[fg=colour237]:#[fg=colour250]#W#[fg=colour244]#F '
      
      # Message styling
      set -g message-style fg=colour232,bg=colour166,bold
      
      # Custom key bindings
      
      # Split panes using | and -
      bind | split-window -h -c "#{pane_current_path}"
      bind - split-window -v -c "#{pane_current_path}"
      unbind '"'
      unbind %

      # Create new window with c, preserving path
      bind c new-window -c "#{pane_current_path}"
      
      # Reload config file
      bind r source-file ~/.config/tmux/tmux.conf \; display "Config Reloaded!"
      
      # Synchronize panes
      bind-key C-s setw synchronize-panes
      
      # Easy session switching with fzf
      bind-key C-j display-popup -E "\
        tmux list-sessions -F '#{?session_attached,,#{session_name}}' |\
        grep -v \"^$\" |\
        fzf --reverse |\
        xargs tmux switch-client -t"
        
      # Smart pane switching with awareness of Vim splits
      is_vim="ps -o state= -o comm= -t '#{pane_tty}' \
          | grep -iqE '^[^TXZ ]+ +(\\S+\\/)?g?(view|n?vim?x?)(diff)?$'"
          
      bind-key -n 'C-h' if-shell "$is_vim" 'send-keys C-h'  'select-pane -L'
      bind-key -n 'C-j' if-shell "$is_vim" 'send-keys C-j'  'select-pane -D'
      bind-key -n 'C-k' if-shell "$is_vim" 'send-keys C-k'  'select-pane -U'
      bind-key -n 'C-l' if-shell "$is_vim" 'send-keys C-l'  'select-pane -R'
      
      # Vi style copy/paste
      bind-key -T copy-mode-vi v send-keys -X begin-selection
      bind-key -T copy-mode-vi y send-keys -X copy-selection-and-cancel
      
      # Toggle status bar
      bind-key b set-option status
      
      # Display pane numbers longer
      set-option -g display-panes-time 2000
      
      # Ensure terminal window titles match tmux window titles
      set-option -g set-titles on
      set-option -g set-titles-string "#S / #W"
      
      # Disable auto rename of windows
      set-option -g allow-rename off
    '';
  };
}