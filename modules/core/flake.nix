# flake-parts wiring: which flake-level module systems exist, which systems we
# build for, and how `pkgs` is instantiated.
{ config, inputs, ... }:
{
  # `flake.modules.<class>.<name>` — the option that makes the dendritic
  # pattern possible: every file under modules/ registers its own aspect there,
  # and modules/hosts/* compose them by taking `attrValues` of a class.
  imports = [ inputs.flake-parts.flakeModules.modules ];

  systems = [ "x86_64-linux" ];

  # One nixpkgs instantiation, shared by the standalone-HM target here and
  # mirrored into NixOS's `nixpkgs.*` (modules/nix.nix) from the same
  # `stubbe.lib.nixpkgsConfig` — so a `pkgs.<x>` reference resolves to the same
  # derivation on either target.
  #
  # This module deliberately declares NOTHING else per-system: a perSystem
  # output declared here would depend on `pkgs`, which is built below from
  # `config.flake.overlays`, whose evaluation forces the transposed perSystem
  # outputs — that output included. Keep other perSystem outputs in their own
  # files; `nix fmt` lives in modules/dev/format.nix.
  #
  # For the same reason the nixpkgs `config` comes from `config.stubbe.lib`
  # (a declared option) and not from `flake.lib` (a freeform output).
  perSystem =
    { system, ... }:
    {
      _module.args.pkgs = import inputs.nixpkgs {
        inherit system;
        config = config.stubbe.lib.nixpkgsConfig;
        overlays = builtins.attrValues config.flake.overlays;
      };
    };
}
