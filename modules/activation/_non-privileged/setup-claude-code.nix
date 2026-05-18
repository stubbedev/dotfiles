{ self, ... }:
{
  enableIf = { config, ... }: config.features.claudeCode;
  args =
    {
      config,
      lib,
      homeLib,
      ...
    }:
    let
      servers = import (self + "/lib/mcp-servers.nix") {
        chromePath = "${config.home.profileDirectory}/bin/google-chrome-stable";
        firefoxPath = "${config.home.profileDirectory}/bin/firefox";
      };
      # Claude's .claude.json shape: { type, command, args, env? }
      toClaude = _: server: {
        type = "stdio";
        inherit (server) command args;
      } // lib.optionalAttrs (server ? env) { inherit (server) env; };
      mcpServers = lib.mapAttrs toClaude servers;
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
            tui = "fullscreen";
            editorMode = "vi";
          };
        }}

        ${homeLib.mergeJsonPatch {
          name = "claude-config-patch";
          target = "${config.home.homeDirectory}/.claude.json";
          patch = {
            inherit mcpServers;
          };
        }}
      '';
    };
}
