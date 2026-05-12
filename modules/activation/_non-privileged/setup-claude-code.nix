_: {
  enableIf = { config, ... }: config.features.claudeCode;
  args =
    {
      config,
      homeLib,
      ...
    }:
    let
      chromeExecutable = "${config.home.profileDirectory}/bin/google-chrome-stable";
      firefoxExecutable = "${config.home.profileDirectory}/bin/firefox";
    in
    {
      actionScript = ''
        ${homeLib.mergeJsonPatch {
          name = "claude-settings-patch";
          target = "${config.home.homeDirectory}/.claude/settings.json";
          patch = {
            statusLine = {
              type = "command";
              command = "cship";
              refreshInterval = 5;
            };
            includeCoAuthoredBy = false;
          };
        }}

        ${homeLib.mergeJsonPatch {
          name = "claude-config-patch";
          target = "${config.home.homeDirectory}/.claude.json";
          patch = {
            mcpServers = {
              chrome-devtools = {
                type = "stdio";
                command = "npx";
                args = [
                  "-y"
                  "chrome-devtools-mcp@latest"
                  "--no-usage-statistics"
                  "--executable-path"
                  chromeExecutable
                ];
              };
              firefox-devtools = {
                type = "stdio";
                command = "npx";
                args = [
                  "-y"
                  "firefox-devtools-mcp@latest"
                  "--firefox-path"
                  firefoxExecutable
                ];
              };
              atlassian-mcp = {
                type = "stdio";
                command = "npx";
                args = [ "-y" "@stubbedev/atlassian-mcp@latest" ];
              };
              sentry-mcp = {
                type = "stdio";
                command = "npx";
                args = [ "-y" "@stubbedev/sentry-mcp@latest" ];
              };
              jenkins-mcp = {
                type = "stdio";
                command = "npx";
                args = [ "-y" "@stubbedev/jenkins-mcp@latest" ];
              };
              nix-mcp = {
                type = "stdio";
                command = "uvx";
                args = [ "mcp-nixos" ];
              };
            };
          };
        }}
      '';
    };
}
