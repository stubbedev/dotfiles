flakeArgs:
let
  inherit ((import ./_helpers.nix)) mkSudoSetupModule;
  dir = ./_privileged;
  nixFiles = builtins.filter
    (n: builtins.match ".*\\.nix$" n != null)
    (builtins.attrNames (builtins.readDir dir));
in
{
  imports = map (n: mkSudoSetupModule ((import (dir + "/${n}")) flakeArgs)) nixFiles;
}
