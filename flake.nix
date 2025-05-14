{
  description = "Aurora Freedom Project Dotfiles";

  inputs = {
    # Hardware NixOS Defination
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    # Nixpkgs
    nixpkgs-darwin.url = "github:NixOS/nixpkgs/nixpkgs-24.11-darwin";
    nixpkgs.url = "github:NixOS/nixpkgs/release-24.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    
    # Home manager
    home-manager = {
      url = "github:nix-community/home-manager/release-24.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    # Nix-darwin for macOS
    darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-24.11";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };

    # Apps
    
    # Zen-browser
    zen-browser.url = "github:0xc000022070/zen-browser-flake";
  };

  outputs = { self, nixpkgs, nixos-hardware, nixpkgs-unstable, nixpkgs-darwin, home-manager, darwin, zen-browser, ... }@inputs:
    let
      traceImport = true;
      # Supported systems
      supportedSystems = [ "x86_64-linux" "x86_64-darwin" "aarch64-linux" "aarch64-darwin" ];
      
      # Helper function to generate an attrset '{ x86_64-linux = f "x86_64-linux"; ... }'
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      
      # Nixpkgs instantiated for supported systems with allowUnfree enabled
      nixpkgsFor = forAllSystems (system: import nixpkgs { 
        inherit system; 
        config = { allowUnfree = true; };
      });
      
      # Get all user profiles from the profiles directory
      getUserProfiles = dir:
        let
          profilesDir = dir + "/home/profiles";
          contents = builtins.readDir profilesDir;
          # Fix: Use nixpkgs.lib.filterAttrs instead of builtins.filterAttrs
          dirNames = builtins.attrNames (nixpkgs.lib.filterAttrs (n: v: v == "directory" && n != "template") contents);
        in
          dirNames;
          
      # Helper function to create Darwin configurations for all users
      mkAllDarwinConfigs = dir:
        let
          users = getUserProfiles dir;
          mkConfig = username: {
            name = "macbook-${username}";
            value = mkDarwinSystem {
              hostname = "macbook-${username}";
              username = username;
            };
          };
        in
          # Make sure this returns an empty set if no users are found
          if users == [] then {} else builtins.listToAttrs (map mkConfig users);
      
      # Helper function to create Darwin configurations
      mkDarwinSystem = { hostname, username, system ? "x86_64-darwin" }: 
        darwin.lib.darwinSystem {
          inherit system;
          modules = [
            ./hosts/darwin/macbook
            ./modules/shared
            ./modules/darwin
            home-manager.darwinModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.${username} = import ./home/profiles/${username};
              nixpkgs.config.allowUnfree = true;
            } 
          ];
        };
    in
    {
      # NixOS configurations
      nixosConfigurations = {
        # Legion laptop configuration
        legion = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
	  specialArgs = { inherit inputs; system = "x86_64-linux"; };
          modules = [
            # Fixed: Directly import your configuration.nix and hardware-configuration.nix
            ./configuration.nix
            ./hardware-configuration.nix
            nixos-hardware.nixosModules.lenovo-legion-15ach6h	    
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.rnd = import ./home.nix;
              nixpkgs.config.allowUnfree = true;
              home-manager.extraSpecialArgs = { inherit inputs; system = "x86_64-linux"; };
            }
          ];
        };
      };
      
      # Darwin (macOS) configurations - more dynamic approach
      darwinConfigurations = 
        # Add static configurations
        {
          # Default macbook configuration
          macbook = mkDarwinSystem { 
            hostname = "macbook"; 
            username = "mike";
          };
        } 
        # Merge with dynamically generated configurations
        // mkAllDarwinConfigs ./.;
      
      # Development shells
      devShells = forAllSystems (system:
        let pkgs = nixpkgsFor.${system}; in {
          default = pkgs.mkShell {
            buildInputs = with pkgs; [
              nixpkgs-fmt
              nil
            ];
          };
        }
      );
    };
}
