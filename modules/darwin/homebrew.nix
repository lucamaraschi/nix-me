# modules/darwin/homebrew.nix
{ config, lib, pkgs, ... }:

{
  # macOS applications managed through Homebrew
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      cleanup = "zap";
    };
    
    # Homebrew taps
    taps = [
    ];
    
    # Command-line tools
    brews = [
      "coreutils"
      "direnv"
      "fd" 
      "gcc"
      "git"
      "grep"
      "helm"
      "jq"
      "k3d"
      "mas"  # Mac App Store CLI
      "pnpm"
      "ripgrep"
      "svn"
      "terraform"
      "trash"
    ];
    
    # macOS applications
    casks = [
      # Communication & Collaboration
      "linear-linear"
      "loom"
      "microsoft-teams"
      "miro"
      "slack"
      "zoom"
      
      # Productivity
      "1password"
      "hiddenbar"
      "raycast"
      "rectangle"
      
      # Development
      "docker"
      "ghostty"
      "github"
      "orbstack"
      "orka-desktop"
      "visual-studio-code"
      
      # Browsers
      "google-chrome"
      
      # Graphics & Design
      "adobe-creative-cloud"
      "figma"
      
      # Microsoft Office
      "microsoft-office"
      
      # Utilities
      "hammerspoon"
      "proton-mail"
      "protonvpn"
      "virtualbuddy"
      "vmware-fusion"
      
      # Media
      "obs"
      "spotify"
    ];
    
    # Mac App Store applications
    masApps = {
      Tailscale = 1475387142;
      Xcode = 497799835;
      "iA-Writer" = 775737590;
    };
  };
  
  # Make sure system knows about installed apps
  system.activationScripts.applications.text = ''
    echo "setting up ~/Applications..." >&2
    rm -rf ~/Applications/Nix\ Apps
    mkdir -p ~/Applications/Nix\ Apps
    
    # Use the applications path from config
    APPS_DIR="${config.system.build.applications}/Applications"
    if [ -d "$APPS_DIR" ]; then
      for app in $(find "$APPS_DIR" -maxdepth 1 -type l 2>/dev/null || echo ""); do
        ln -sf "$app" ~/Applications/Nix\ Apps/
      done
    else
      echo "Applications directory not found at $APPS_DIR" >&2
    fi
  '';
}