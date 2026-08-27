_: {
  flake.modules.homeManager.homeTargets =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    lib.mkIf (config.host.platform != "nixos") {
      targets.genericLinux = {
        enable = true;
        nixGL = {
          packages = pkgs.nixgl;
        };
      };
    };
}
