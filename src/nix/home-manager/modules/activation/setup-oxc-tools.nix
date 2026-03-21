_:
let
  order = import ./_order.nix;
in
{
  flake.modules.homeManager.activationSetupOxcTools =
    {
      pkgs,
      lib,
      ...
    }:
    {
      home.activation.setupOxcTools = lib.hm.dag.entryAfter order.after.setupOxcTools ''
        bun="${pkgs.bun}/bin/bun"
        "$bun" add --global oxlint oxfmt >/dev/null 2>&1
      '';
    };
}
