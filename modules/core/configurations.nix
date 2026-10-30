{
  lib,
  config,
  inputs,
  withSystem,
  nixpkgsFor,
  ...
}:
let
  flakeAttrModule = name: { host.flakeAttr = name; };
  sharedFlakeAttrModule = name: { home-manager.sharedModules = [ (flakeAttrModule name) ]; };

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
    nixOnDroid = lib.mkOption {
      type = lib.types.lazyAttrsOf hostOptions;
      default = { };
      description = ''
        Android hosts, built by nix-on-droid inside the Termux app. The
        attribute name is what `nix-on-droid switch --flake .#<name>` selects.
      '';
    };
  };

  config.flake = {
    homeConfigurations = lib.mapAttrs (
      name: host:
      withSystem host.system (
        { pkgs, ... }:
        inputs.home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            host.module
            (flakeAttrModule name)
          ];
        }
      )
    ) config.configurations.homeManager;

    nixosConfigurations = lib.mapAttrs (
      name: host:
      inputs.nixpkgs.lib.nixosSystem {
        inherit (host) system;
        modules = [
          host.module
          (sharedFlakeAttrModule name)
        ];
      }
    ) config.configurations.nixos;

    nixOnDroidConfigurations = lib.mapAttrs (
      name: host:
      inputs.nix-on-droid.lib.nixOnDroidConfiguration {
        pkgs = nixpkgsFor host.system;
        modules = [
          host.module
          (sharedFlakeAttrModule name)
        ];
        # nix-on-droid otherwise loads its own 2024 home-manager, whose
        # stdlib-extended and module set predate every option this repo uses.
        home-manager-path = inputs.home-manager.outPath;
      }
    ) config.configurations.nixOnDroid;
  };
}
