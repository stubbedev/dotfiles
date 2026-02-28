_: {
  flake.modules.homeManager.programsFirefox =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    lib.mkIf config.features.desktop {
      programs.firefox = {
        enable = true;
      };
    };
}
