# Branch of the pkgs.stubbe helper tree (see ./default.nix).
# Repo files and secrets: store paths carved out of the flake source.
_: {
  stubbe.pkgsLib = {
    # Never reference ${self}/src/x directly: that depends on the whole flake
    # source, so the hash churns on every commit and privileged activations
    # re-prompt. builtins.path hashes the file's own contents.
    file =
      { lib, stubbe, ... }:
      relPath:
      builtins.path {
        path = stubbe.src + "/${relPath}";
        name = lib.replaceStrings [ "/" ] [ "-" ] relPath;
      };

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
