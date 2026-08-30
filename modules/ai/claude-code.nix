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

        # ── Language servers ────────────────────────────────────────────
        # Claude Code speaks LSP itself. A plugin manifest's `lspServers` makes
        # it spawn the matching server for any file it reads or edits, and it
        # subscribes to textDocument/publishDiagnostics -- what comes back is
        # attached to the Edit/Write that caused it. That is the whole "the
        # agent sees its own type errors" story; an MCP LSP *bridge* is a
        # second process tree re-implementing a client this one already has.
        #
        # `command` is an absolute store path, so none of these land on PATH.
        # They are the same attrs modules/nvim.nix puts in the nvim wrapper, so
        # this adds no closure, and a server starts only when a file with its
        # extension is actually touched -- editing nix costs nixd, nothing else.
        #
        # Deliberately a SUBSET of src/nvim/lua/lsp.lua: Claude Code binds one
        # server per extension and drops the rest ("extension .go already
        # handled by gopls"), so where nvim stacks a type-checker and a linter
        # the type-checker wins -- ty over ruff, tsgo over oxlint, gopls over
        # golangci-lint. Servers whose value is formatting or completion
        # (oxfmt, html, marksman) are left out: only diagnostics reach Claude.
        lspServers =
          let
            vscodeLs = bin: "${pkgs.vscode-langservers-extracted}/bin/${bin}";
          in
          {
            nixd = {
              command = lib.getExe' pkgs.nixd "nixd";
              extensionToLanguage.".nix" = "nix";
              # ponytail: static nixpkgs eval only. src/nvim/lua/nixd.lua also
              # feeds nixd this flake's nixos/home-manager option sets, which is
              # what makes *option name* diagnostics work -- resolving those
              # needs the host, and there is no before_init hook here to do it
              # lazily. Undefined variables, arity and type errors still land.
              #
              # No diagnostic.suppress: nixf 2.9 has no "sema-escaping-with"
              # sname any more, and nixd logs "unknown" for it on every publish.
              # (src/nvim/lua/lsp.lua still passes it -- same dead setting.)
              settings.nixd.nixpkgs.expr = "import <nixpkgs> { }";
            };

            # One Go binary; no node, no tsserver. Same reasoning as nvim.
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

            # phpantom already carries the Blade directive table, and .blade.php
            # matches on its trailing .php, so one entry covers both.
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

        # Servers reach Claude Code only through a plugin, and a marketplace is
        # a directory on disk -- so render one into the store rather than
        # hand-maintain the JSON under src/. A `directory` marketplace is only
        # ever read, so a read-only store path is fine.
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
                    # The plugin ships no commands/agents/skills directories.
                    strict = false;
                  }
                )
              ];
            };
            "plugins/lsp/.claude-plugin/plugin.json" = json "plugin.json" manifest;
            # Claude Code reads the servers from `.lsp.json` in the plugin root
            # (equivalently `lspServers` inline in plugin.json).
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
