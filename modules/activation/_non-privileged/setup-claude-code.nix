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
      toClaude =
        _: server:
        {
          type = "stdio";
          inherit (server) command args;
        }
        // lib.optionalAttrs (server ? env) { inherit (server) env; };
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
            # official php-lsp plugin. Local marketplace lives in the
            # live src checkout; the phpantom_lsp binary is on PATH via
            # modules/packages/php.nix.
            extraKnownMarketplaces = {
              phpantom.source = {
                source = "directory";
                path = "${config.home.homeDirectory}/.stubbe/src/claude/phpantom-lsp";
              };
              # Caveman: ultra-compressed comms mode. Plugin self-registers
              # its SessionStart/UserPromptSubmit hooks via plugin.json
              # (${CLAUDE_PLUGIN_ROOT}), so enabling it here is enough — no
              # need to wire hooks in settings.json. Default mode is "full"
              # (caveman-config.js), so every session starts caveman-on.
              caveman.source = {
                source = "github";
                repo = "JuliusBrussee/caveman";
              };
            };
            enabledPlugins = {
              "phpantom-lsp@phpantom" = true;
              "php-lsp@claude-plugins-official" = false;
              "caveman@caveman" = true;
            };
          };
        }}

        ${homeLib.mergeJsonPatch {
          name = "caveman-config";
          # caveman-config.js resolves $XDG_CONFIG_HOME/caveman/config.json,
          # falling back to ~/.config/caveman/config.json. Pin defaultMode so
          # caveman starts "full" on every session regardless of the plugin's
          # built-in default drifting in a future update.
          target = "${config.home.homeDirectory}/.config/caveman/config.json";
          patch.defaultMode = "full";
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
