{
  description = "Home Manager Config";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixGL = {
      url = "github:nix-community/nixGL";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { ... }@inputs: {
    homeConfigurations."stubbe" =
      inputs.home-manager.lib.homeManagerConfiguration {
        pkgs = import inputs.nixpkgs {
          system = "x86_64-linux";
          config = {
            allowUnfree = true;
            allowUnfreePredicate = (_: true);
            allowInsecure = true;
            allowInsecurePredicate = (_: true);
          };
          overlays = [
            inputs.nixGL.overlay
          ];
        };
        extraSpecialArgs = inputs;
        modules = [ ./home.nix ];
      };
  };
}

