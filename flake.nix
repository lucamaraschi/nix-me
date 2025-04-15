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
  };

  outputs = inputs@{ nixpkgs, darwin, home-manager, ... }:
    let
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
            
            # Set hostname and machine name
            { 
              networking = {
                hostName = hostname;
                computerName = machineName;
                localHostName = machineName;
              };
            }
            
            # Include home-manager
            home-manager.darwinModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.${builtins.getEnv "USER"} = import ./modules/home-manager;
            }
            
            # Overlays
            {
              nixpkgs.overlays = [
                (import ./overlays/nodejs.nix)
                # Add other overlays here
              ];
            }
          ] ++ extraModules;
          specialArgs = { inherit inputs hostname machineType machineName; };
        };
    in
    {
      # Define specific machine configurations
      darwinConfigurations = {
        # MacBook configurations
        "macbook-pro" = mkDarwinSystem { 
          hostname = "macbook-pro";
          machineType = "macbook";
          machineName = "MacBook Pro";
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
        
        # Dynamic configuration (used by the Makefile)
        "${builtins.getEnv "HOSTNAME"}" = 
          if builtins.getEnv "HOSTNAME" != "" then
            let
              hostname = builtins.getEnv "HOSTNAME";
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
    };
}