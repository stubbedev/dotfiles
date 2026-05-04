_: {
  flake.modules.homeManager.xdgOpencode =
    {
      homeLib,
      lib,
      config,
      ...
    }:
    lib.mkIf config.features.opencode {
      xdg.configFile = (homeLib.xdgSources [
        "opencode/tui.json"
        "opencode/AGENTS.md"
        "opencode/themes/catppuccin-mocha.json"
        "opencode/agents"
      ]) // {
        "opencode/opencode.json" = {
          text = builtins.toJSON (
            lib.recursiveUpdate (builtins.fromJSON (homeLib.xdgContent "opencode/opencode.json")) {
              mcp.chrome-devtools = {
                type = "local";
                command = [
                  "npx"
                  "-y"
                  "chrome-devtools-mcp@latest"
                  "--no-usage-statistics"
                  "--executable-path"
                  "${config.home.homeDirectory}/.nix-profile/bin/google-chrome-stable"
                ];
              };
            }
          );
          force = true;
        };
      };

      home.sessionVariables = {
        OPENCODE_DISABLE_CLAUDE_CODE = 1;
      };
    };
}
