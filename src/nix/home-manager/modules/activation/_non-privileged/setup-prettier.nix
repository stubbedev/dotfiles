_: {
  moduleName = "activationSetupPrettier";
  activationName = "setupPrettier";
  args =
    { pkgs, ... }:
    {
      actionScript = ''
        bun="${pkgs.bun}/bin/bun"
        "$bun" add --global prettier >/dev/null 2>&1
      '';
    };
}
