{
  inputs,
  self,
  ...
}:
{
  flake.modules.nixos.home-manager-bridge =
    { ... }:
    {
      imports = [ inputs.home-manager.nixosModules.home-manager ];

      # nixpkgs.config + overlays live in modules/nixos/nix-settings.nix.
      # useGlobalPkgs makes HM read those same overlaid pkgs, so HM modules
      # under home-manager.users.<name> see pkgs.nixgl, pkgs.cship, etc.

      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.extraSpecialArgs = {
        inherit inputs self;
      };
    };
}
