{
  description = "Home Manager configuration of stubbe";

  inputs = {
    # Specify the source of Home Manager and Nixpkgs.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixGL = {
      url = "github:guibou/nixGL";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, nixGL, ... }:
    {
      homeConfigurations."stubbe" = home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs {
          system = "x86_64-linux";
          config = {
            allowUnfree = true;
            allowUnfreePredicate = (_: true);
            allowInsecure = true;
            allowInsecurePredicate = (_: true);
          };
        };
        extraSpecialArgs = {
          inherit nixGL;
          inherit self;
        };
        modules = [ ./home.nix ];
      };
    };
}

