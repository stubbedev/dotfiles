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
        pkgs.claude-code
        pkgs.cship
      ];

      xdg.configFile = homeLib.xdgSourceAt "cship.toml" "cship/cship.toml";
    };
}
