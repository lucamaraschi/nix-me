{
  description = "My Mac configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-generators.url = "github:nix-community/nixos-generators";
  };

  outputs = inputs@{ self, nixpkgs, darwin, home-manager, ... }:
    let
        defaultUsername = "lucamaraschi";
        username = let
          detected = builtins.getEnv "USERNAME";
        in if detected != "" then detected else defaultUsername;

        # Check if we're running in VM mode (skip Mac App Store apps)
        skipMasApps = builtins.getEnv "SKIP_MAS_APPS" == "1";

      # Function to create a darwin configuration
      mkDarwinSystem = {
        hostname,
        machineType ? null,
        machineName ? hostname,
        system ? "aarch64-darwin",
        username ? "lucamaraschi",
        extraModules ? []
      }:
        darwin.lib.darwinSystem {
          inherit system;
          modules = [
            # Base shared configuration
            ./hosts/types/shared

            # Machine-type specific configuration (if specified)
            (if machineType != null then ./hosts/types/${machineType} else {})

            # Host-specific configuration (if it exists)
            (if builtins.pathExists ./hosts/machines/${hostname}
            then ./hosts/machines/${hostname}
            else {})

            # Set hostname, machine name, and primary user
            {
              networking = {
                hostName = hostname;
                computerName = machineName;
                localHostName = machineName;
              };

              # Fix for primary user requirement
              system.primaryUser = username;

              # Explicit user configuration
              users.users.${username} = {
                name = username;
                home = "/Users/${username}";
              };

              users.users.root.home = "/var/root";
            }

            # Include home-manager
            home-manager.darwinModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "backup";

              home-manager.extraSpecialArgs = { inherit username; };
              home-manager.users.${username} = import ./modules/home-manager;
            }

            # Overlays
            {
              nixpkgs.overlays = [
                (import ./overlays/nodejs.nix)
                # Add other overlays here
              ];
            }

            # VM mode - skip Mac App Store apps (iCloud doesn't work in VMs)
            (if skipMasApps then ./modules/darwin/vm-mode.nix else {})
          ] ++ extraModules;
          specialArgs = {
            inherit inputs hostname machineType machineName username;
          };
  };
    in
    {
      # Define specific machine configurations
      darwinConfigurations = {
        # MacBook configurations
        "gotham" = mkDarwinSystem {
          hostname = "gotham";
          machineType = "macbook";
          machineName = "Gotham";
        };

        # Work laptop with dev + work profiles
        "nabucodonosor" = mkDarwinSystem {
          hostname = "nabucodonosor";
          machineType = "macbook";
          machineName = "Nabucodonosor";
          username = "batman";
          extraModules = [
            ./hosts/profiles/dev.nix   # Development tools
            ./hosts/profiles/work.nix  # Work collaboration apps
          ];
        };

        "macbook-air" = mkDarwinSystem {
          hostname = "macbook-air";
          machineType = "macbook";
          machineName = "MacBook Air";
        };

        # MacBook Pro configurations
        # Work laptop with dev + work profiles
        "bellerofonte" = mkDarwinSystem {
          hostname = "bellerofonte";
          machineType = "macbook-pro";
          machineName = "Bellerofonte";
          username = "batman";
          extraModules = [
            ./hosts/profiles/dev.nix   # Development tools
            ./hosts/profiles/work.nix  # Work collaboration apps
          ];
        };

        # Mac Mini configurations
        "mac-mini" = mkDarwinSystem {
          hostname = "mac-mini";
          machineType = "macmini";
          machineName = "Mac Mini";
        };

        # VM configurations
        "vm-test" = mkDarwinSystem {
          hostname = "vm-test";
          machineType = "vm";
          machineName = "VM";
          username = username;  # Use USERNAME env var or default
        };

        # Add a generic VM configuration for testing
        "nixos-vm" = mkDarwinSystem {
          hostname = "nixos-vm";
          machineType = "vm";
          machineName = "NixOS VM";
        };

        # ========================================
        # Multi-profile configuration examples
        # ========================================
        # Profiles are composable! Combine them as needed:
        #   - dev.nix      → IDEs, languages, dev tools
        #   - work.nix     → Slack, Teams, Zoom, etc.
        #   - personal.nix → Spotify, OBS, media tools

        # Work developer machine (dev + work)
        "work-macbook-pro" = mkDarwinSystem {
          hostname = "work-macbook-pro";
          machineType = "macbook-pro";
          machineName = "Work MacBook Pro";
          username = "batman";
          extraModules = [
            ./hosts/profiles/dev.nix
            ./hosts/profiles/work.nix
          ];
        };

        # Personal dev machine (dev + personal)
        "personal-macbook-pro" = mkDarwinSystem {
          hostname = "personal-macbook-pro";
          machineType = "macbook-pro";
          machineName = "Personal MacBook Pro";
          username = "batman";
          extraModules = [
            ./hosts/profiles/dev.nix
            ./hosts/profiles/personal.nix
          ];
        };

        # Full-stack machine (all profiles)
        "work-macbook" = mkDarwinSystem {
          hostname = "work-macbook";
          machineType = "macbook";
          machineName = "Work MacBook";
          username = "batman";
          extraModules = [
            ./hosts/profiles/dev.nix
            ./hosts/profiles/work.nix
            ./hosts/profiles/personal.nix  # For after-hours
          ];
        };

        # Home media/streaming station (personal only, no dev)
        "home-studio" = mkDarwinSystem {
          hostname = "home-studio";
          machineType = "macmini";
          machineName = "Home Studio";
          username = "batman";
          extraModules = [
            ./hosts/profiles/personal.nix
          ];
        };

        # Minimal base (no profiles - just essentials)
        "minimal-mac" = mkDarwinSystem {
          hostname = "minimal-mac";
          machineType = "macbook";
          machineName = "Minimal Mac";
          username = "batman";
          # No extraModules = truly minimal base only
        };
      };

      nixosConfigurations = {
        nixos-vm = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          specialArgs = { inherit inputs username; };
          modules = [
            ./hosts/machines/nixos-vm/default.nix
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                users.dev = import ./hosts/machines/nixos-vm/home.nix;
                extraSpecialArgs = { inherit inputs username; };
              };
            }
          ];
        };
      };

      # Standalone home-manager configurations (for non-NixOS systems)
      homeConfigurations = {
      };

      # packages = {
      #   aarch64-darwin = {
      #     vm-manager = pkgs.writeShellApplication {
      #       name = "vm-manager";
      #       text = builtins.readFile ./scripts/vm-manager.sh;
      #     };
      #   };
      # };
    };
}
