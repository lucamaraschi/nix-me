{
  description = "My Mac configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-25.05-darwin";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nixpkgs, nixpkgs-unstable, darwin, home-manager, ... }:
    let
      defaultUsername = "lucamaraschi";
      username =
        let
          detected = builtins.getEnv "USERNAME";
        in
        if detected != "" then detected else defaultUsername;

      # Check if we're running in VM mode (skip Mac App Store apps)
      skipMasApps = builtins.getEnv "SKIP_MAS_APPS" == "1";

      mkUnstablePkgs =
        system:
        import nixpkgs-unstable {
          inherit system;
          config.allowUnfree = true;
        };

      # Function to create a darwin configuration
      mkDarwinSystem =
        { hostname
        , machineType ? null
        , machineName ? hostname
        , system ? "aarch64-darwin"
        , username ? "lucamaraschi"
        , extraModules ? [ ]
        }:
        darwin.lib.darwinSystem {
          inherit system;
          modules = [
            # Base shared configuration
            ./nix/hosts/types/shared

            # Machine-type specific configuration (if specified)
            (if machineType != null then ./nix/hosts/types/${machineType} else { })

            # Host-specific configuration (if it exists)
            (if builtins.pathExists ./nix/hosts/machines/${hostname}
            then ./nix/hosts/machines/${hostname}
            else { })

            # Set hostname, machine name, and primary user
            {
              networking = {
                hostName = hostname;
                computerName = machineName;
                localHostName = hostname;
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

              home-manager.extraSpecialArgs = {
                inherit inputs username;
                unstablePkgs = mkUnstablePkgs system;
              };
              home-manager.users.${username} = import ./nix/modules/home-manager;
            }

            # Overlays
            {
              nixpkgs.overlays = [
                (import ./nix/overlays/airjack.nix)
                # Add other overlays here
              ];
            }

            # VM mode - skip Mac App Store apps (iCloud doesn't work in VMs)
            (if skipMasApps then ./nix/modules/darwin/vm-mode.nix else { })
          ] ++ extraModules;
          specialArgs = {
            inherit inputs hostname machineType machineName username;
            unstablePkgs = mkUnstablePkgs system;
          };
        };
    in
    {
      packages = nixpkgs.lib.genAttrs [
        "aarch64-darwin"
        "x86_64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ]
        (system:
          let pkgs = import nixpkgs { inherit system; };
          in {
            nix-me-apps = pkgs.rustPlatform.buildRustPackage {
              pname = "nix-me-apps";
              version = "0.1.0";
              src = pkgs.lib.cleanSourceWith {
                src = ./packages/app-state/engine;
                filter = path: type:
                  let base = baseNameOf path;
                  in base != "target" && base != ".git";
              };
              cargoLock.lockFile = ./packages/app-state/engine/Cargo.lock;
              cargoBuildFlags = [ "-p" "nix-me-apps" ];
              cargoTestFlags = [ "-p" "nix-me-apps" ];
              meta.mainProgram = "nix-me-apps";
            };
            default = self.packages.${system}.nix-me-apps;
          });

      # Define specific machine configurations
      darwinConfigurations = {
        # MacBook configurations
        "gotham" = mkDarwinSystem {
          hostname = "gotham";
          machineType = "macbook";
          machineName = "Gotham";
        };

        # Work laptop with dev + coding agents + work profiles
        "nabucodonosor" = mkDarwinSystem {
          hostname = "nabucodonosor";
          machineType = "macbook";
          machineName = "Nabucodonosor";
          username = "batman";
          extraModules = [
            ./nix/hosts/profiles/dev.nix # Development tools
            ./nix/hosts/profiles/coding-agents.nix # AI coding agents
            ./nix/hosts/profiles/work.nix # Work collaboration apps
            ./nix/hosts/profiles/personal.nix # Media tools for tutorials/streaming
            ./nix/hosts/profiles/hacking.nix # Hacking tools for on the go
            ./nix/hosts/profiles/maker.nix # 3D printing & CAD
          ];
        };

        "macbook-air" = mkDarwinSystem {
          hostname = "macbook-air";
          machineType = "macbook";
          machineName = "MacBook Air";
        };

        # MacBook Pro configurations
        # Work laptop with dev + coding agents + work profiles
        "bellerofonte" = mkDarwinSystem {
          hostname = "bellerofonte";
          machineType = "macbook-pro";
          machineName = "Bellerofonte";
          username = "batman";
          extraModules = [
            ./nix/hosts/profiles/dev.nix # Development tools
            ./nix/hosts/profiles/coding-agents.nix # AI coding agents
            ./nix/hosts/profiles/work.nix # Work collaboration apps
            ./nix/hosts/profiles/personal.nix # Media tools for tutorials/streaming
            ./nix/hosts/profiles/hacking.nix # Hacking tools for on the go
            ./nix/hosts/profiles/maker.nix # 3D printing & CAD
            ./nix/hosts/profiles/ai.nix
          ];
        };

        # Mac Mini configurations
        "mac-mini" = mkDarwinSystem {
          hostname = "mac-mini";
          machineType = "macmini";
          machineName = "Mac Mini";
        };

        # Zion - Maker/craft station (3D printing, CAD, design)
        "zion" = mkDarwinSystem {
          hostname = "zion";
          machineType = "macmini";
          machineName = "Zion";
          username = "batman";
          extraModules = [
            ./nix/hosts/profiles/dev.nix # Development tools
            ./nix/hosts/profiles/coding-agents.nix # AI coding agents
            ./nix/hosts/profiles/work.nix # Work collaboration apps
            ./nix/hosts/profiles/personal.nix # Media tools for tutorials/streaming
            ./nix/hosts/profiles/maker.nix # 3D printing & CAD
          ];
        };

        # VM configurations
        "vm-test" = mkDarwinSystem {
          hostname = "vm-test";
          machineType = "vm";
          machineName = "VM";
          username = username; # Use USERNAME env var or default
          # Exercise the opt-in activation path in the disposable macOS VM.
          extraModules = [{ apps.state.enable = true; }];
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
        #   - local-ai.nix → Local DeepSeek inference through DS4 and Pi

        # Work developer machine (dev + coding agents + work)
        "work-macbook-pro" = mkDarwinSystem {
          hostname = "work-macbook-pro";
          machineType = "macbook-pro";
          machineName = "Work MacBook Pro";
          username = "batman";
          extraModules = [
            ./nix/hosts/profiles/dev.nix
            ./nix/hosts/profiles/coding-agents.nix
            ./nix/hosts/profiles/work.nix
          ];
        };

        # Personal dev machine (dev + coding agents + personal)
        "personal-macbook-pro" = mkDarwinSystem {
          hostname = "personal-macbook-pro";
          machineType = "macbook-pro";
          machineName = "Personal MacBook Pro";
          username = "batman";
          extraModules = [
            ./nix/hosts/profiles/dev.nix
            ./nix/hosts/profiles/coding-agents.nix
            ./nix/hosts/profiles/personal.nix
          ];
        };

        # Local AI machine (dev + private DeepSeek coding agent)
        "local-ai-macbook-pro" = mkDarwinSystem {
          hostname = "local-ai-macbook-pro";
          machineType = "macbook-pro";
          machineName = "Local AI MacBook Pro";
          username = "batman";
          extraModules = [
            ./nix/hosts/profiles/dev.nix
            ./nix/hosts/profiles/local-ai.nix
          ];
        };

        # Full-stack machine (dev + coding agents + work + personal)
        "work-macbook" = mkDarwinSystem {
          hostname = "work-macbook";
          machineType = "macbook";
          machineName = "Work MacBook";
          username = "batman";
          extraModules = [
            ./nix/hosts/profiles/dev.nix
            ./nix/hosts/profiles/coding-agents.nix
            ./nix/hosts/profiles/work.nix
            ./nix/hosts/profiles/personal.nix # For after-hours
          ];
        };

        # Home media/streaming station (personal only, no dev)
        "home-studio" = mkDarwinSystem {
          hostname = "home-studio";
          machineType = "macmini";
          machineName = "Home Studio";
          username = "batman";
          extraModules = [
            ./nix/hosts/profiles/personal.nix
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

        # Security testing / ethical hacking setup
        "hacking-mac" = mkDarwinSystem {
          hostname = "hacking-mac";
          machineType = "macbook";
          machineName = "Hacking Lab";
          username = "batman";
          extraModules = [
            ./nix/hosts/profiles/dev.nix # Development tools
            ./nix/hosts/profiles/coding-agents.nix # AI coding agents
            ./nix/hosts/profiles/hacking.nix # Security/pentesting tools
          ];
        };
      };

      nixosConfigurations = {
        nixos-vm = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          specialArgs = { inherit inputs username; };
          modules = [
            ./nix/hosts/machines/nixos-vm/default.nix
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                users.dev = import ./nix/hosts/machines/nixos-vm/home.nix;
                extraSpecialArgs = { inherit inputs username; };
              };
            }
          ];
        };
      };

      # Standalone home-manager configurations (for non-NixOS systems)
      homeConfigurations = { };

      # packages = {
      #   aarch64-darwin = {
      #     vm-manager = pkgs.writeShellApplication {
      #       name = "vm-manager";
      #       text = builtins.readFile ./tools/development/vm-manager.sh;
      #     };
      #   };
      # };
    };
}
