{
  lib,
  config,
  inputs,
  ...
}:
{
  options.configurations.nixos = lib.mkOption {
    type = lib.types.lazyAttrsOf (
      lib.types.submodule (_: {
        options = {
          system = lib.mkOption {
            type = lib.types.str;
          };
          module = lib.mkOption {
            type = lib.types.deferredModule;
          };
          extraSpecialArgs = lib.mkOption {
            type = lib.types.attrs;
            default = { };
          };
        };
      })
    );
    default = { };
  };

  config.flake.nixosConfigurations = lib.mapAttrs (
    _: cfg:
    inputs.nixpkgs.lib.nixosSystem {
      inherit (cfg) system;
      specialArgs = cfg.extraSpecialArgs // {
        inherit inputs;
      };
      modules = [ cfg.module ];
    }
  ) config.configurations.nixos;
}
