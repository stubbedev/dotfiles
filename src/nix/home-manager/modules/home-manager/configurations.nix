{ lib, config, inputs, withSystem, ... }:
{
  options.configurations.homeManager = lib.mkOption {
    type = lib.types.lazyAttrsOf (lib.types.submodule ({ ... }: {
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
    }));
    default = { };
  };

  config.flake.homeConfigurations =
    lib.mapAttrs (name: cfg:
      withSystem cfg.system ({ pkgs, ... }:
        inputs.home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          extraSpecialArgs = cfg.extraSpecialArgs // { inherit pkgs; };
          modules = [ cfg.module ];
        })
    ) config.configurations.homeManager;
}
