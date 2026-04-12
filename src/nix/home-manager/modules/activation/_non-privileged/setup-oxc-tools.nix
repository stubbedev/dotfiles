_: {
  moduleName = "activationSetupOxcTools";
  activationName = "setupOxcTools";
  args =
    { pkgs, ... }:
    {
      actionScript = ''
        bun="${pkgs.bun}/bin/bun"
        "$bun" add --global oxlint oxfmt >/dev/null 2>&1
      '';
    };
}
