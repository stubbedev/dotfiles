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
