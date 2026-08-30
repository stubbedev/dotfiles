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
        # Claude Code sources the user's zsh before every Bash call, so the agent
        # inherits interactive aliases that block on prompts nobody can answer.
        # The unalias must be on its OWN LINE: zsh expands aliases while parsing
        # a line, so a `;`-joined one comes too late.
        # Functions survive on purpose: hm, treeman and gwt are functions.
        # No permissionDecision: "allow" here would auto-approve every Bash call.
        noAliasesHook = pkgs.writeShellScript "claude-hook-no-aliases" ''
          exec ${lib.getExe pkgs.jq} -c '{hookSpecificOutput:{hookEventName:"PreToolUse",updatedInput:(.tool_input+{command:("unalias -a 2>/dev/null\n"+.tool_input.command)})}}'
        '';

        lspServers =
          let
            vscodeLs = bin: "${pkgs.vscode-langservers-extracted}/bin/${bin}";
          in
          {
            nixd = {
              command = lib.getExe' pkgs.nixd "nixd";
              extensionToLanguage.".nix" = "nix";
              # No diagnostic.suppress: nixf 2.9 has no "sema-escaping-with"
              # sname any more, and nixd logs "unknown" for it on every publish.
              # (src/nvim/lua/lsp.lua still passes it -- same dead setting.)
              settings.nixd.nixpkgs.expr = "import <nixpkgs> { }";
            };

            tsgo = {
              command = lib.getExe' pkgs.typescript-go "tsgo";
              args = [
                "--lsp"
                "--stdio"
              ];
              extensionToLanguage = {
                ".ts" = "typescript";
                ".mts" = "typescript";
                ".cts" = "typescript";
                ".tsx" = "typescriptreact";
                ".js" = "javascript";
                ".mjs" = "javascript";
                ".cjs" = "javascript";
                ".jsx" = "javascriptreact";
              };
            };

            vue_ls = {
              command = lib.getExe' pkgs.vue-language-server "vue-language-server";
              args = [ "--stdio" ];
              extensionToLanguage.".vue" = "vue";
            };

            svelte = {
              command = lib.getExe' pkgs.svelte-language-server "svelteserver";
              args = [ "--stdio" ];
              extensionToLanguage.".svelte" = "svelte";
            };

            # .blade.php matches on its trailing .php, so this covers Blade too.
            phpantom = {
              command = lib.getExe' pkgs.phpantom_lsp "phpantom_lsp";
              extensionToLanguage.".php" = "php";
            };

            gopls = {
              command = lib.getExe' pkgs.gopls "gopls";
              extensionToLanguage.".go" = "go";
              settings.gopls = {
                gofumpt = true;
                analyses = {
                  unusedparams = true;
                  shadow = true;
                };
                staticcheck = true;
              };
            };

            templ = {
              command = lib.getExe' pkgs.templ "templ";
              args = [ "lsp" ];
              extensionToLanguage.".templ" = "templ";
            };

            ty = {
              command = lib.getExe' pkgs.ty "ty";
              args = [ "server" ];
              extensionToLanguage.".py" = "python";
            };

            rust_analyzer = {
              command = lib.getExe' pkgs.rust-analyzer "rust-analyzer";
              extensionToLanguage.".rs" = "rust";
            };

            lua_ls = {
              command = lib.getExe' pkgs.lua-language-server "lua-language-server";
              extensionToLanguage.".lua" = "lua";
              settings.Lua = {
                runtime.version = "LuaJIT";
                diagnostics.globals = [ "vim" ];
                workspace.checkThirdParty = false;
                telemetry.enable = false;
              };
            };

            bashls = {
              command = lib.getExe' pkgs.bash-language-server "bash-language-server";
              args = [ "start" ];
              extensionToLanguage = {
                ".sh" = "shellscript";
                ".bash" = "shellscript";
                ".zsh" = "shellscript";
              };
            };

            jsonls = {
              command = vscodeLs "vscode-json-language-server";
              args = [ "--stdio" ];
              extensionToLanguage = {
                ".json" = "json";
                ".jsonc" = "jsonc";
              };
              initializationOptions.provideFormatter = false;
            };

            cssls = {
              command = vscodeLs "vscode-css-language-server";
              args = [ "--stdio" ];
              extensionToLanguage = {
                ".css" = "css";
                ".scss" = "scss";
                ".less" = "less";
              };
              initializationOptions.provideFormatter = false;
              settings = {
                css.validate = true;
                scss.validate = true;
              };
            };

            yamlls = {
              command = lib.getExe' pkgs.yaml-language-server "yaml-language-server";
              args = [ "--stdio" ];
              extensionToLanguage = {
                ".yaml" = "yaml";
                ".yml" = "yaml";
              };
              settings.yaml.keyOrdering = false;
            };

            taplo = {
              command = lib.getExe' pkgs.taplo "taplo";
              args = [
                "lsp"
                "stdio"
              ];
              extensionToLanguage.".toml" = "toml";
            };

            sqruff = {
              command = lib.getExe' pkgs.sqruff "sqruff";
              args = [ "lsp" ];
              extensionToLanguage.".sql" = "sql";
            };
          };

        # lspServers is only reachable through a plugin, and a marketplace is a
        # directory on disk. Read-only is fine: a directory marketplace is never
        # written to.
        lspMarketplace =
          let
            manifest = {
              name = "lsp";
              description = "Language servers for Claude Code's built-in LSP client";
              version = "1.0.0";
            };
            json = name: value: (pkgs.formats.json { }).generate name value;
          in
          pkgs.linkFarm "claude-lsp-marketplace" {
            ".claude-plugin/marketplace.json" = json "marketplace.json" {
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
            "plugins/lsp/.claude-plugin/plugin.json" = json "plugin.json" manifest;
            "plugins/lsp/.lsp.json" = json "lsp.json" lspServers;
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
            };
          }}

          # Marketplaces and plugin enablement go through jsonSet, not the merge
          # above: a merge is additive, so a marketplace dropped from this file
          # would linger in the live settings.json and Claude Code would keep
          # reporting its plugin as missing. Same reasoning as .mcpServers below.
          ${pkgs.stubbe.jsonSet {
            name = "claude-marketplaces";
            target = "${config.home.homeDirectory}/.claude/settings.json";
            key = "extraKnownMarketplaces";
            value = {
              # Language servers, generated above. Replaces the hand-written
              # src/claude/phpantom-lsp marketplace, which only ever registered
              # .php -- so every other language Claude edited here came back
              # with no diagnostics at all.
              lsp.source = {
                source = "directory";
                path = "${lspMarketplace}";
              };
              # Caveman: ultra-compressed comms mode. Plugin self-registers
              # its SessionStart/UserPromptSubmit hooks via plugin.json
              # (''${CLAUDE_PLUGIN_ROOT}), so enabling it here is enough — no
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
          }}

          ${pkgs.stubbe.jsonSet {
            name = "claude-enabled-plugins";
            target = "${config.home.homeDirectory}/.claude/settings.json";
            key = "enabledPlugins";
            value = {
              "lsp@lsp" = true;
              "caveman@caveman" = true;
              "ponytail@ponytail" = true;
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
