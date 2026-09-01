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
        lspServers =
          let
            vscodeLs = bin: "${pkgs.vscode-langservers-extracted}/bin/${bin}";
          in
          {
            nixd = {
              command = lib.getExe' pkgs.nixd "nixd";
              extensionToLanguage.".nix" = "nix";
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
            "plugins/lsp/.lsp.json" = pkgs.stubbe.gen.json "lsp.json" lspServers;
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

          ${pkgs.stubbe.setup.jsonSet {
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

          ${pkgs.stubbe.setup.jsonMerge {
            name = "caveman-config";
            target = "${config.home.homeDirectory}/.config/caveman/config.json";
            patch.defaultMode = "full";
          }}

          ${pkgs.stubbe.setup.jsonMerge {
            name = "ponytail-config";
            target = "${config.home.homeDirectory}/.config/ponytail/config.json";
            patch.defaultMode = "full";
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
