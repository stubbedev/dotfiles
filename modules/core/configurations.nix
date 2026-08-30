# Note the absence of `extraSpecialArgs` / `specialArgs`: nothing is injected
# into a module. Values that used to travel that way now reach modules the two
# ways the module system already provides — `pkgs.stubbe.*` for helpers and
# data (modules/core/pkgs-stubbe.nix), and `config.stubbe.*` / `config.host.*`
# for anything derived from the configuration itself. Flake inputs are resolved
# at flake-parts level inside each aspect file, where `inputs` is in scope
# anyway. This is what makes every module movable between the two targets
# without rewiring.
{
  lib,
  config,
  inputs,
  withSystem,
  ...
}:
let
  hostOptions = lib.types.submodule {
    options = {
      system = lib.mkOption {
        type = lib.types.str;
        description = "Nix system double this host is built for.";
      };
      module = lib.mkOption {
        type = lib.types.deferredModule;
        description = "The host's top-level module, normally composing `attrValues config.flake.modules.<class>`.";
      };
    };
  };
in
{
  options.configurations = {
    homeManager = lib.mkOption {
      type = lib.types.lazyAttrsOf hostOptions;
      default = { };
      description = "Standalone home-manager hosts — non-NixOS distros.";
    };
    nixos = lib.mkOption {
      type = lib.types.lazyAttrsOf hostOptions;
      default = { };
      description = "NixOS hosts.";
    };
  };

  config.flake = {
    homeConfigurations = lib.mapAttrs (
      _name: host:
      withSystem host.system (
        { pkgs, ... }:
        inputs.home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [ host.module ];
        }
      )
    ) config.configurations.homeManager;

    nixosConfigurations = lib.mapAttrs (
      _name: host:
      inputs.nixpkgs.lib.nixosSystem {
        inherit (host) system;
        modules = [ host.module ];
      }
    ) config.configurations.nixos;
  };
}
