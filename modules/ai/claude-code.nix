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
    lib.mkIf config.features.claudeCode {
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
            model = "claude-opus-5-5";
          };
        }}

        ${pkgs.stubbe.setup.jsonSet {
          name = "claude-config-mcp";
          target = "${config.home.homeDirectory}/.claude.json";
          key = "mcpServers";
          # Authoritative: the managed set fully owns .mcpServers. notmuch and
          # devenv are the global servers; everything else comes from a repo's
          # .mcp.json, so dropped entries disappear instead of lingering.
          value =
            lib.optionalAttrs config.features.desktop {
              notmuch-mcp = {
                type = "stdio";
                command = "notmuch-mcp";
                args = [ ];
              };
            }
            // lib.optionalAttrs config.features.development {
              devenv-mcp = {
                type = "stdio";
                command = "devenv-mcp";
                args = [ ];
              };
            };
        }}
      '';
    };
}
