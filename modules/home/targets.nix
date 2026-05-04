_: {
  linuxOnlyHomeModules.targets =
    { pkgs, ... }:
    {
      targets.genericLinux = {
        enable = true;
        nixGL = {
          packages = pkgs.nixgl;
        };
      };
    };
}
