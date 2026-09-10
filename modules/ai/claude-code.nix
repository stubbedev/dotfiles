# Settings are patched into the LIVE file with jq at activation time: merging
# at eval time would drop anything Claude Code wrote in between.
_: {
  flake.modules.homeManager.claudeCode =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    lib.mkIf config.features.claudeCode (
      let
        lspMarketplace =
          let
            manifest = {
              name = "lsp";
              description = "Language servers for Claude Code's built-in LSP client";
              version = "1.0.0";
            };
          in
          pkgs.linkFarm "claude-lsp-marketplace" {
            ".claude-plugin/marketplace.json" = pkgs.stubbe.gen.json "marketplace.json" {
              "$schema" = "https://anthropic.com/claude-code/marketplace.json";
              inherit (manifest) name description;
              owner.name = "stubbedev";
              plugins = [
                (
                  manifest
                  // {
                    source = "./plugins/lsp";
                    category = "development";
                    strict = false;
                  }
                )
              ];
            };
            "plugins/lsp/.claude-plugin/plugin.json" = pkgs.stubbe.gen.json "plugin.json" manifest;
            "plugins/lsp/.lsp.json" = pkgs.stubbe.gen.json "lsp.json" config.stubbe.lsp.clients.claude;
          };
      in
      {
        home.packages = [
          (config.stubbe.gfx.bundle {
            pkg = pkgs.claude-code;
            gfx = false;
            flags = [ "--dangerously-skip-permissions" ];
          })
          pkgs.cship
        ];

        xdg.configFile."cship.toml".source = pkgs.stubbe.gen.toml "cship.toml" {
          cship = {
            lines = [ "$directory$git_branch$git_status $cship.usage_limits $cship.model.id" ];
            usage_limits = {
              seven_day_format = "";
              separator = "";
              five_hour_format = "{remaining}%";
            };
          };
        };

        stubbe.setup.claudeCode.script = ''
          ${
            let
              retired = [
                "caveman"
                "ponytail"
              ];
              known = "${config.home.homeDirectory}/.claude/plugins/known_marketplaces.json";
              stalePaths = lib.concatMap (plugin: [
                "${config.home.homeDirectory}/.config/${plugin}"
                "${config.home.homeDirectory}/.claude/plugins/marketplaces/${plugin}"
                "${config.home.homeDirectory}/.claude/plugins/cache/${plugin}"
              ]) retired;
            in
            ''
              rm -rf ${lib.escapeShellArgs stalePaths}

              if [ -f ${known} ]; then
                ${lib.getExe pkgs.jq} 'del(${lib.concatMapStringsSep ", " (p: ".\"${p}\"") retired})' \
                  ${known} > ${known}.hm-tmp && mv ${known}.hm-tmp ${known}
              fi
            ''
          }

          ${pkgs.stubbe.setup.jsonMerge {
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
              # Alias guard lives in zsh: modules/shell.nix sets no_aliases for
              # non-interactive shells. Empty list prunes the old PreToolUse
              # hook out of settings.json (jsonMerge replaces arrays).
              hooks.PreToolUse = [ ];
              model = "claude-opus-5[1m]";
            };
          }}

          ${pkgs.stubbe.setup.jsonSet {
            name = "claude-marketplaces";
            target = "${config.home.homeDirectory}/.claude/settings.json";
            key = "extraKnownMarketplaces";
            value = {
              lsp.source = {
                source = "directory";
                path = "${lspMarketplace}";
              };
            };
          }}

          ${pkgs.stubbe.setup.jsonSet {
            name = "claude-enabled-plugins";
            target = "${config.home.homeDirectory}/.claude/settings.json";
            key = "enabledPlugins";
            value = {
              "lsp@lsp" = true;
            }
            # The official LSP plugins fight the generated one for the same
            # extensions -- first registered wins and the loser never starts --
            # and each invokes a bare binary name off PATH, which on this
            # machine only nvim's wrapper has. gopls-lsp and rust-analyzer-lsp
            # ship enabled by default, so listing them is not hypothetical.
            // lib.genAttrs [
              "gopls-lsp@claude-plugins-official"
              "lua-lsp@claude-plugins-official"
              "php-lsp@claude-plugins-official"
              "pyright-lsp@claude-plugins-official"
              "rust-analyzer-lsp@claude-plugins-official"
              "typescript-lsp@claude-plugins-official"
            ] (_: false);
          }}

          ${pkgs.stubbe.setup.jsonSet {
            name = "claude-config-mcp";
            target = "${config.home.homeDirectory}/.claude.json";
            key = "mcpServers";
            # Authoritative: the managed set fully owns .mcpServers, so servers
            # dropped from modules/ai/mcp-servers.nix disappear instead of lingering.
            value = config.stubbe.mcp.clients.claude;
          }}
        '';
      }
    );
}
