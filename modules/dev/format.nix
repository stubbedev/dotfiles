# `nix fmt` — nixfmt-tree wraps nixfmt in treefmt, so a bare `nix fmt` formats
# the whole tree. (nixfmt-rfc-style is a deprecated alias these days.)
_: {
  perSystem =
    { pkgs, ... }:
    {
      formatter = pkgs.nixfmt-tree;
    };
}
