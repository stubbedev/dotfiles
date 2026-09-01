# Branch of the pkgs.stubbe helper tree (see ./default.nix).
# The shared palette in the encodings different config formats want.
_: {
  stubbe.pkgsLib = {
    withHash =
      { lib, stubbe, ... }:
      lib.mapAttrs (_: hex: "#${hex}") stubbe.colors;
    withArgb =
      { lib, stubbe, ... }:
      lib.mapAttrs (_: hex: "0xff${hex}") stubbe.colors;
  };
}
