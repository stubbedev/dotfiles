_: {
  flake.modules.homeManager.claudeCode =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      model = "claude-opus-5-5";
    in
    lib.mkIf config.features.claudeCode {
      home.packages = [
        (config.stubbe.gfx.bundle {
          pkg = pkgs.claude-code;
          gfx = false;
          flags = [ "--dangerously-skip-permissions" ];
          env = {
            CLAUDE_CODE_DISABLE_INLINE_SHELL_RM_PROMPT = "1";
            CLAUDE_CODE_DISABLE_SUBSTITUTION_RM_PROMPT = "1";
          };
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

      # Credentials only: each server reads its config from
      # ~/.config/<name>/config.json when a client spawns it as stdio. There
      # are no MCP services or ports to manage any more.
      sops.secrets = lib.listToAttrs (
        map
          (
            provider:
            lib.nameValuePair "${provider}_mcp" (
              pkgs.stubbe.secret {
                name = "${provider}-mcp.json";
                path = "${config.home.homeDirectory}/.config/${provider}-mcp/config.json";
              }
            )
          )
          [
            "atlassian"
            "jenkins"
            "sentry"
            "ds"
          ]
      );

      stubbe.setup.claudeCode.script = ''
        ${pkgs.stubbe.setup.jsonWrite {
          name = "claude-settings";
          target = "${config.home.homeDirectory}/.claude/settings.json";
          value = {
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
            theme = "auto";
            inherit model;
            modelSettings.${model}.effortLevel = "high";
            switchModelsOnFlag = false;
            agentPushNotifEnabled = true;
            permissions.defaultMode = "bypassPermissions";
            skipDangerousModePermissionPrompt = true;
          };
        }}

        ${pkgs.stubbe.setup.jsonSet {
          name = "claude-config-mcp";
          target = "${config.home.homeDirectory}/.claude.json";
          key = "mcpServers";
          # Authoritative: the managed set fully owns .mcpServers. notmuch is
          # the global server; everything else comes from a repo's .mcp.json,
          # so dropped entries disappear instead of lingering.
          value = lib.optionalAttrs config.features.desktop {
            notmuch-mcp = {
              type = "stdio";
              command = "notmuch-mcp";
              args = [ ];
            };
          };
        }}
      '';
    };
}
