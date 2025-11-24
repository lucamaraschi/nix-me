{ pkgs, config, lib, ... }:

{
  # MacBook Pro-specific settings
  # Inherits from macbook but adds Pro-specific optimizations

  imports = [
    # Import base macbook configuration
    ../macbook/default.nix
  ];

  system.defaults = {
    # MacBook Pro typically has larger display
    dock = {
      tilesize = lib.mkForce 36; # Slightly larger than regular MacBook
    };

    # More performance-oriented settings
    CustomUserPreferences = {
      "com.apple.controlcenter".BatteryShowPercentage = true;

      # Enable high performance mode (for M1 Pro/Max/Ultra)
      "com.apple.SystemProfiler" = {
        "PerformanceMode" = "high";
      };
    };
  };

  # MacBook Pro power management (less aggressive than MacBook Air)
  system.activationScripts.macbookProOptimization.text = ''
    echo "Setting energy preferences for MacBook Pro..." >&2

    # MacBook Pro can handle more aggressive performance settings
    pmset -b displaysleep 20    # 20 min on battery (vs 15 for regular)
    pmset -c displaysleep 0     # Never sleep on power

    # Enable power nap on both battery and power
    pmset -b powernap 1
    pmset -c powernap 1

    # Less aggressive disk sleep
    pmset -b disksleep 15       # 15 min on battery
    pmset -c disksleep 0        # Never on power
  '';

  # MacBook Pro typically has more resources, can handle more dev tools
  apps = {
    # Add development packages via Nix
    systemPackagesToAdd = [
      "kubernetes-helm"  # Helm CLI via Nix
    ];

    # Note: docker-desktop is already in base installations.nix
    # Additional Pro-specific tools can be added here as needed
  };
}
