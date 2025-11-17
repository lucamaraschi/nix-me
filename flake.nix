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
            ./hosts/shared

            # Machine-type specific configuration (if specified)
            (if machineType != null then ./hosts/${machineType} else {})

            # Host-specific configuration (if it exists)
            (if builtins.pathExists ./hosts/${hostname}
            then ./hosts/${hostname}
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

        "nabucodonosor" = mkDarwinSystem {
          hostname = "nabucodonosor";
          machineType = "macbook";
          machineName = "Nabucodonosor";
          username = "batman";
        };

        "macbook-air" = mkDarwinSystem {
          hostname = "macbook-air";
          machineType = "macbook";
          machineName = "MacBook Air";
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
        # Profile-based configurations examples
        # ========================================

        # MacBook Pro with Work profile
        "work-macbook-pro" = mkDarwinSystem {
          hostname = "work-macbook-pro";
          machineType = "macbook-pro";
          machineName = "Work MacBook Pro";
          username = "batman";
          extraModules = [
            ./hosts/profiles/work.nix
          ];
        };

        # MacBook Pro with Personal profile
        "personal-macbook-pro" = mkDarwinSystem {
          hostname = "personal-macbook-pro";
          machineType = "macbook-pro";
          machineName = "Personal MacBook Pro";
          username = "batman";
          extraModules = [
            ./hosts/profiles/personal.nix
          ];
        };

        # Regular MacBook with Work profile
        "work-macbook" = mkDarwinSystem {
          hostname = "work-macbook";
          machineType = "macbook";
          machineName = "Work MacBook";
          username = "batman";
          extraModules = [
            ./hosts/profiles/work.nix
          ];
        };

        # Mac Mini with Personal profile (home workstation)
        "home-studio" = mkDarwinSystem {
          hostname = "home-studio";
          machineType = "macmini";
          machineName = "Home Studio";
          username = "batman";
          extraModules = [
            ./hosts/profiles/personal.nix
          ];
        };
      };

      nixosConfigurations = {
        nixos-vm = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          specialArgs = { inherit inputs username; };
          modules = [
            ./hosts/nixos-vm/default.nix
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                users.dev = import ./hosts/nixos-vm/home.nix;
                extraSpecialArgs = { inherit inputs username; };
              };
            }
          ];
        };
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
