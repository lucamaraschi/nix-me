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

  outputs = inputs@{ nixpkgs, darwin, home-manager, ... }:
    let
    # Function to determine username from various sources
      getUsername = 
        # Try several methods to find the username, in order of preference
      let
        # 1. Check if USER env var is set
        fromEnv = builtins.getEnv "USER";
        
        # 2. Try to get from the HOME path
        fromHome = let
          home = builtins.getEnv "HOME";
          parts = if home != "" then builtins.split "/" home else [];
          lastIndex = if builtins.length parts > 0 then builtins.length parts - 1 else 0;
          username = if lastIndex > 0 then builtins.elemAt parts lastIndex else "";
        in username;
        
        # 3. Fall back to LOGNAME
        fromLogname = builtins.getEnv "LOGNAME";
        
        # 4. Last resort default
        defaultUser = "lucamaraschi";
      in
        if fromEnv != "" then fromEnv
        else if fromHome != "" then fromHome
        else if fromLogname != "" then fromLogname
        else defaultUser;
      
      username = getUsername;
      
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
            }
            
            # Include home-manager
            home-manager.darwinModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;

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
        
        # Dynamic configuration (used by the Makefile) - handle specific hostname cases
        "${if builtins.getEnv "HOSTNAME" == "Gotham" then "gotham" else builtins.getEnv "HOSTNAME"}" = 
          if builtins.getEnv "HOSTNAME" != "" then
            let
              rawHostname = builtins.getEnv "HOSTNAME";
              # Normalize known problematic hostnames
              hostname = if rawHostname == "Gotham" then "gotham" else rawHostname;
              machineType = builtins.getEnv "MACHINE_TYPE";
              machineName = builtins.getEnv "MACHINE_NAME";
            in
            mkDarwinSystem { 
              inherit hostname;
              machineType = if machineType != "" then machineType else null;
              machineName = if machineName != "" then machineName else hostname;
            }
          else mkDarwinSystem { hostname = "macbook-pro"; machineType = "macbook"; };
      };

      nixosConfigurations = {
        nixos-vm = nixpkgs.lib.nixosSystem {
          system = if builtins.match ".*aarch64.*" builtins.currentSystem != null then "aarch64-linux" else "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [
            ./hosts/nixos-vm/default.nix
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                users.dev = import ./hosts/nixos-vm/home.nix;
                extraSpecialArgs = { inherit inputs; };
              };
            }
          ];
        };
      };

      packages = {
        aarch64-darwin = {
          vm-manager = 
            let pkgs = nixpkgs.legacyPackages.aarch64-darwin;
            in pkgs.writeShellApplication {
              name = "vm-manager";
              text = ''
                echo "Creating NixOS VM..."
                nix build .#nixosConfigurations.nixos-vm.config.system.build.toplevel
                echo "VM system built!"
              '';
            };
        };
      };
    };
}