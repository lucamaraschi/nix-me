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
    for app in $(find ${pkgs.config.system.build.applications}/Applications -maxdepth 1 -type l); do
      ln -sf "$app" ~/Applications/Nix\ Apps/
    done
  '';
}