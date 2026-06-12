{ inputs, ... }:
{
  imports = [ inputs.flake-parts.flakeModules.modules ];

  perSystem =
    { pkgs, ... }:
    {
      # nixfmt-tree wraps nixfmt in treefmt so `nix fmt` (no args) formats
      # the whole tree; nixfmt-rfc-style is a deprecated alias these days.
      formatter = pkgs.nixfmt-tree;
    };
}
