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
            model = "claude-opus-4-8[1m]";
            # Use the PHPantom language server for .php instead of the
            # official intelephense plugin. Local marketplace lives in the
            # live src checkout; the phpantom_lsp binary is on PATH via
            # modules/packages/php.nix.
            extraKnownMarketplaces.phpantom.source = {
              source = "local";
              path = "${config.home.homeDirectory}/.stubbe/src/claude/phpantom-lsp";
            };
            enabledPlugins = {
              "phpantom-lsp@phpantom" = true;
              "php-lsp@claude-plugins-official" = false;
            };
          };
        }}

        ${homeLib.setJsonKey {
          name = "claude-config-mcp";
          target = "${config.home.homeDirectory}/.claude.json";
          key = "mcpServers";
          # Authoritative: the managed set fully owns .mcpServers, so servers
          # dropped from lib/mcp-servers.nix disappear instead of lingering.
          value = mcpServers;
        }}
      '';
    };
}
