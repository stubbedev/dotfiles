{ ... }:
{
  flake.modules.homeManager.xdgOpencode = { homeLib, ... }: {
    xdg.configFile = homeLib.xdgSources [
      "opencode/opencode.json"
      "opencode/AGENTS.md"
      "opencode/themes/catppuccin-mocha.json"
    ];
  };
}
