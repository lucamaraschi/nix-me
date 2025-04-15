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