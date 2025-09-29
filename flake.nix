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
      # username = builtins.getEnv "USERNAME";
      # debug = builtins.trace "username: ${username}" username;

      usernameFromEnv = builtins.getEnv "USERNAME";
      userFromEnv = builtins.getEnv "USER";

      # Debug what we're getting
      debug = builtins.trace "USERNAME env: '${usernameFromEnv}', USER env: '${userFromEnv}'" null;

      # Use USERNAME if set, otherwise fall back
      username = if usernameFromEnv != "" then usernameFromEnv
                else if userFromEnv != "" && userFromEnv != "root" then userFromEnv
                else throw "No username detected. Run: make USERNAME=yourusername switch";
      # #Function to determine username from various sources
      # getUsername =
      #   let
      #     fromEnv = builtins.getEnv "USER";
      #     fromSudoUser = builtins.getEnv "SUDO_USER";

      #     # Use SUDO_USER if available (original user before sudo), otherwise use USER but not if it's root
      #     result = if fromSudoUser != "" then fromSudoUser
      #             else if fromEnv != "" && fromEnv != "root" then fromEnv
      #             else "batman";  # fallback to known user

      #     debug = builtins.trace "USER: '${fromEnv}', SUDO_USER: '${fromSudoUser}', result: '${result}'" null;
      #   in
      #     result;
      # username = getUsername;
      # forceEval = builtins.trace "Forced username evaluation: ${username}" null;

      # Function to create a darwin configuration
      mkDarwinSystem = {
        hostname,
        machineType ? null,
        machineName ? hostname,
        system ? "aarch64-darwin",
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
        };

        # Add a generic VM configuration for testing
        "nixos-vm" = mkDarwinSystem {
          hostname = "nixos-vm";
          machineType = "vm";
          machineName = "NixOS VM";
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
