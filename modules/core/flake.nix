# flake-parts wiring: which flake-level module systems exist, which systems we
# build for, how `pkgs` is instantiated, and what `nix fmt` runs.
{ config, inputs, ... }:
{
  # `flake.modules.<class>.<name>` — the option that makes the dendritic
  # pattern possible: every file under modules/ registers its own aspect there,
  # and modules/hosts/* compose them by taking `attrValues` of a class.
  imports = [ inputs.flake-parts.flakeModules.modules ];

  systems = [ "x86_64-linux" ];

  perSystem =
    { pkgs, system, ... }:
    {
      # One nixpkgs instantiation, shared by the standalone-HM target here and
      # mirrored into NixOS's `nixpkgs.*` (modules/nix.nix) from the same
      # `flake.lib.nixpkgsConfig` — so a `pkgs.<x>` reference resolves to the
      # same derivation on either target.
      _module.args.pkgs = import inputs.nixpkgs {
        inherit system;
        config = config.flake.lib.nixpkgsConfig;
        overlays = builtins.attrValues config.flake.overlays;
      };

      # nixfmt-tree wraps nixfmt in treefmt, so bare `nix fmt` formats the
      # whole tree; nixfmt-rfc-style is a deprecated alias these days.
      formatter = pkgs.nixfmt-tree;
    };
}
