# Branch of the pkgs.stubbe helper tree (see ./default.nix).
# Secrets: sops files carved out of the flake source.
_: {
  stubbe.pkgsLib = {
    secret =
      { lib, stubbe, ... }:
      {
        name,
        path ? null,
      }:
      {
        sopsFile = stubbe.src + "/secrets/${name}";
        format = "binary";
      }
      // lib.optionalAttrs (path != null) { inherit path; };
  };
}
