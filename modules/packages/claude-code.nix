_: {
  flake.modules.homeManager.packagesClaudeCode =
    {
      pkgs,
      lib,
      config,
      homeLib,
      ...
    }:
    lib.mkIf config.features.claudeCode {
      home.packages = [
        (homeLib.mkWrappedPackage {
          pkg = pkgs.claude-code;
          gfx = false;
          flags = [ "--dangerously-skip-permissions" ];
        })
        pkgs.cship
      ];

      xdg.configFile = homeLib.xdgSource "cship/cship.toml" { target = "cship.toml"; };
    };
}
