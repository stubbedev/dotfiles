_:
let
  order = import ./_order.nix;
in
{
  flake.modules.homeManager.activationSetupPrettier =
    {
      pkgs,
      lib,
      ...
    }:
    {
      home.activation.setupPrettier = lib.hm.dag.entryAfter order.after.setupPrettier ''
        bun="${pkgs.bun}/bin/bun"
        "$bun" add --global prettier >/dev/null 2>&1
      '';
    };
}
