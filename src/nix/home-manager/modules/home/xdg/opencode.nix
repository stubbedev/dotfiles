{ ... }:
{
  flake.modules.homeManager.xdgOpencode = { homeLib, lib, config, ... }:
    lib.mkIf config.features.opencode {
      xdg.configFile = homeLib.xdgSources [
        "opencode/opencode.json"
        "opencode/AGENTS.md"
      "opencode/themes/catppuccin-mocha.json"
      ];
    };
}
