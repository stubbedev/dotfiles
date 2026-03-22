_: {
  flake.modules.homeManager.xdgOpencode =
    {
      homeLib,
      lib,
      config,
      ...
    }:
    lib.mkIf config.features.opencode {
      xdg.configFile = homeLib.xdgSources [
        "opencode/opencode.json"
        "opencode/tui.json"
        "opencode/AGENTS.md"
        "opencode/themes/catppuccin-mocha.json"
        "opencode/agents"
      ];

      home.sessionVariables = {
        OPENCODE_DISABLE_CLAUDE_CODE = 1;
      };
    };
}
