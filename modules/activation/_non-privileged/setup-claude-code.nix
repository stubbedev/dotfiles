{ self, inputs, ... }:
{
  enableIf = { config, ... }: config.features.claudeCode;
  args =
    {
      config,
      lib,
      pkgs,
      homeLib,
      ...
    }:
    let
      servers = import (self + "/lib/mcp-servers-wired.nix") {
        inherit
          self
          inputs
          pkgs
          config
          ;
      };
      mcpClients = import (self + "/lib/mcp-client-configs.nix") {
        inherit lib servers;
      };
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
            # Retention sweep for ~/.claude/{projects,tasks,shell-snapshots,
            # backups}. Default is 30 days; 14 keeps ~/.claude/projects (500 MB
            # over 400+ transcripts) in check. Deliberately unconditional — an
            # older session is not worth keeping even if it was /rename'd.
            cleanupPeriodDays = 14;
            tui = "fullscreen";
            editorMode = "vi";
            model = "claude-opus-5[1m]";
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
              # Ponytail: minimal-code-gen discipline (YAGNI decision ladder,
              # fewer LOC). Orthogonal to caveman — caveman compresses prose,
              # ponytail constrains the code written. Self-registers its
              # lifecycle hooks via the plugin manifest; needs node on PATH.
              ponytail.source = {
                source = "github";
                repo = "DietrichGebert/ponytail";
              };
            };
            enabledPlugins = {
              "phpantom-lsp@phpantom" = true;
              "php-lsp@claude-plugins-official" = false;
              "caveman@caveman" = true;
              "ponytail@ponytail" = true;
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

        ${homeLib.mergeJsonPatch {
          name = "ponytail-config";
          # Ponytail resolves ~/.config/ponytail/config.json (or
          # $PONYTAIL_DEFAULT_MODE). Pin defaultMode so every session starts at
          # a known intensity regardless of the plugin's built-in default.
          target = "${config.home.homeDirectory}/.config/ponytail/config.json";
          patch.defaultMode = "full";
        }}

        ${homeLib.setJsonKey {
          name = "claude-config-mcp";
          target = "${config.home.homeDirectory}/.claude.json";
          key = "mcpServers";
          # Authoritative: the managed set fully owns .mcpServers, so servers
          # dropped from lib/mcp-servers.nix disappear instead of lingering.
          value = mcpClients.claudeServers;
        }}
      '';
    };
}
