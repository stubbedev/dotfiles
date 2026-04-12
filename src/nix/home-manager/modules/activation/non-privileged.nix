flakeArgs:
let
  inherit ((import ./_helpers.nix)) mkSetupModule;
  dir = ./_non-privileged;
  nixFiles = builtins.filter
    (n: builtins.match ".*\\.nix$" n != null)
    (builtins.attrNames (builtins.readDir dir));
in
{
  imports = map (n: mkSetupModule ((import (dir + "/${n}")) flakeArgs)) nixFiles;
}
