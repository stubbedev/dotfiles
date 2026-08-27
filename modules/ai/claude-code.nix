# Claude Code: the wrapped CLI, and the settings/state files that live outside
# Nix because the tool rewrites them itself.
#
# Every settings write goes through `pkgs.stubbe.jsonMerge`/`jsonSet`, which
# patch the LIVE file with jq at activation time. Merging at eval time against
# `builtins.readFile` would silently drop anything Claude Code wrote between
# evaluation and activation.
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
        # PreToolUse hook: strip shell aliases from every agent-run command.
        #
        # Claude Code snapshots the user's zsh (aliases AND functions) into
        # ~/.claude/shell-snapshots/ and sources it before every Bash call, so the
        # agent inherits `cp -i` / `mv -i` / `rm -i` (which block on a y/n prompt
        # nobody can answer) and TUI/pager substitutes like `ls`→eza. The hook
        # rewrites tool_input.command via hookSpecificOutput.updatedInput, putting
        # `unalias -a` on its OWN LINE ahead of the command: zsh expands aliases
        # while parsing a line, so a `;`-joined `unalias -a` would come too late —
        # the alias on that same line is already expanded.
        #
        # Aliases only. Shell FUNCTIONS survive on purpose: the useful CLI
        # entrypoints here (hm, treeman, gwt, …) are functions, and killing those
        # would break the commands the agent is supposed to run.
        #
        # No permissionDecision is emitted — updatedInput alone is honored, and
        # returning "allow" here would auto-approve every Bash call.
        noAliasesHook = pkgs.writeShellScript "claude-hook-no-aliases" ''
          exec ${lib.getExe pkgs.jq} -c '{hookSpecificOutput:{hookEventName:"PreToolUse",updatedInput:(.tool_input+{command:("unalias -a 2>/dev/null\n"+.tool_input.command)})}}'
        '';
      in
      {
        home.packages = [
          (config.stubbe.gfx.bundle {
            pkg = pkgs.claude-code;
            gfx = false;
            flags = [ "--dangerously-skip-permissions" ];
          })
          # cship renders the status line configured below.
          pkgs.cship
        ];

        # cship reads a flat ~/.config/cship.toml, not a subdirectory.
        xdg.configFile."cship.toml".source = (pkgs.formats.toml { }).generate "cship.toml" {
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
          ${pkgs.stubbe.jsonMerge {
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
              # See noAliasesHook above. Matches the Bash tool and pty-mcp's
              # one-shot `run` (same `command` field, same login-shell aliases);
              # interactive pty sessions are left alone — a human may be driving
              # them and wants their own aliases.
              hooks.PreToolUse = [
                {
                  matcher = "Bash|mcp__pty-mcp__run";
                  hooks = [
                    {
                      type = "command";
                      command = "${noAliasesHook}";
                    }
                  ];
                }
              ];
              model = "claude-opus-5[1m]";
              # Use the PHPantom language server for .php instead of the
              # official php-lsp plugin. Local marketplace lives in the
              # live src checkout; the phpantom_lsp binary is on PATH via
              # modules/php.nix.
              extraKnownMarketplaces = {
                phpantom.source = {
                  source = "directory";
                  path = "${config.stubbe.paths.dotfiles}/src/claude/phpantom-lsp";
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

          ${pkgs.stubbe.jsonMerge {
            name = "caveman-config";
            # caveman-config.js resolves $XDG_CONFIG_HOME/caveman/config.json,
            # falling back to ~/.config/caveman/config.json. Pin defaultMode so
            # caveman starts "full" on every session regardless of the plugin's
            # built-in default drifting in a future update.
            target = "${config.home.homeDirectory}/.config/caveman/config.json";
            patch.defaultMode = "full";
          }}

          ${pkgs.stubbe.jsonMerge {
            name = "ponytail-config";
            # Ponytail resolves ~/.config/ponytail/config.json (or
            # $PONYTAIL_DEFAULT_MODE). Pin defaultMode so every session starts at
            # a known intensity regardless of the plugin's built-in default.
            target = "${config.home.homeDirectory}/.config/ponytail/config.json";
            patch.defaultMode = "full";
          }}

          ${pkgs.stubbe.jsonSet {
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
