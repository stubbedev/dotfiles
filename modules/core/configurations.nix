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

    nixOnDroidConfigurations = lib.mapAttrs (
      _name: host:
      inputs.nix-on-droid.lib.nixOnDroidConfiguration {
        pkgs = import inputs.nixpkgs {
          inherit (host) system;
          config = config.stubbe.lib.nixpkgsConfig;
          overlays = builtins.attrValues config.flake.overlays;
        };
        modules = [ host.module ];
        # nix-on-droid otherwise loads its own 2024 home-manager, whose
        # stdlib-extended and module set predate every option this repo uses.
        home-manager-path = inputs.home-manager.outPath;
      }
    ) config.configurations.nixOnDroid;
  };
}
