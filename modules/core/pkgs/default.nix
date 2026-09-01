# Trunk of the pkgs-level helper tree.
#
# Three layers decide where a helper belongs, by what it needs to exist:
#
#   stubbe.lib.*     (modules/core/lib.nix)  pure data and pure functions -
#                    colors, theme, src. Needs nothing, so this overlay can
#                    consume it without recursion.
#   pkgs.stubbe.*    (here + modules/core/pkgs/*.nix)  anything that BUILDS or
#                    needs `pkgs`. Re-exports all of stubbe.lib, so
#                    pkgs.stubbe.colors resolves too.
#   config.stubbe.*  (paths/gfx/setup/mutable/mcp)  needs the evaluated config
#                    ($HOME, hostname, features) or must merge contributions
#                    from many modules.
#
# Branches graft themselves on by setting `stubbe.pkgsLib.<name>`, a function
# of { final, lib, stubbe } - the final package set, its lib, and the assembled
# stubbe set itself. Each sibling file owns one concern; a leaf module anywhere
# in the tree can add its own without touching this file. Helpers reach each
# other through `stubbe`, which resolves lazily, so ordering never matters.
{ config, lib, ... }:
{
  options.stubbe.pkgsLib = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.raw;
    default = { };
    description = ''
      Helpers grafted onto `pkgs.stubbe`:
      `stubbe.pkgsLib.<name> = { final, lib, stubbe, ... }: <value>`.
    '';
  };

  config.flake.overlays.stubbe =
    final: _prev:
    let
      stubbe = config.stubbe.lib // lib.mapAttrs (_: build: build args) config.stubbe.pkgsLib;
      args = {
        inherit final stubbe;
        inherit (final) lib;
      };
    in
    {
      inherit stubbe;
    };
}
