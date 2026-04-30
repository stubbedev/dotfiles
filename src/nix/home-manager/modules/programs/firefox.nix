_: {
  flake.modules.homeManager.programsFirefox =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    lib.mkIf config.features.browsers {
      programs.firefox = {
        enable = true;
        configPath = "${config.xdg.configHome}/mozilla/firefox";
      };
    };
}
