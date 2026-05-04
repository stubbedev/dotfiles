flakeArgs@{ lib, ... }:
let
  inherit ((import ./_helpers.nix)) mkSudoSetupModule;
  dir = ./_privileged;
  nixFiles = builtins.filter
    (n: builtins.match ".*\\.nix$" n != null)
    (builtins.attrNames (builtins.readDir dir));
in
{
  imports = map (n:
    let attrs = (import (dir + "/${n}")) flakeArgs;
    in mkSudoSetupModule ({ name = "privileged-${lib.removeSuffix ".nix" n}"; } // attrs)
  ) nixFiles;
}
