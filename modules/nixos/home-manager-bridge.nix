{
  config,
  inputs,
  self,
  ...
}:
{
  flake.modules.nixos.home-manager-bridge =
    { ... }:
    {
      imports = [ inputs.home-manager.nixosModules.home-manager ];

      # Share the same overlays the standalone HM build uses, so HM modules
      # under home-manager.users.<name> see pkgs.nixgl, pkgs.cship, etc.
      nixpkgs.overlays = builtins.attrValues config.flake.overlays;
      nixpkgs.config = {
        allowUnfree = true;
        allowInsecure = true;
      };

      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.extraSpecialArgs = {
        inherit inputs self;
      };
    };
}
