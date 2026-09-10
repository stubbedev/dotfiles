# One inventory of language servers, rendered into each CLI's dialect -- the
# same idea as mcp-clients.nix, so adding a server is a one-place edit.
# opencode is deliberately absent: its built-ins resolve binaries off a wrapper
# PATH instead (see modules/ai/opencode.nix).
_: {
  flake.modules.homeManager.lspClients =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      vscodeLs = bin: "${pkgs.vscode-langservers-extracted}/bin/${bin}";

      # Neutral shape per server: `languages` maps a file extension (sans dot)
      # to the LSP language id -- every consumer needs both halves, claude as
      # extensionToLanguage, crush as filetypes (extensions match by suffix).
      servers = {
        nixd = {
          command = lib.getExe' pkgs.nixd "nixd";
          languages.nix = "nix";
          settings.nixd.nixpkgs.expr = "import <nixpkgs> { }";
        };

        tsc = {
          command = lib.getExe pkgs.typescript;
          args = [
            "--lsp"
            "--stdio"
          ];
          languages = {
            ts = "typescript";
            mts = "typescript";
            cts = "typescript";
            tsx = "typescriptreact";
            js = "javascript";
            mjs = "javascript";
            cjs = "javascript";
            jsx = "javascriptreact";
          };
        };

        vue_ls = {
          command = lib.getExe' pkgs.vue-language-server "vue-language-server";
          args = [ "--stdio" ];
          languages.vue = "vue";
        };

        svelte = {
          command = lib.getExe' pkgs.svelte-language-server "svelteserver";
          args = [ "--stdio" ];
          languages.svelte = "svelte";
        };

        phpantom = {
          command = lib.getExe' pkgs.phpantom_lsp "phpantom_lsp";
          languages.php = "php";
        };

        gopls = {
          command = lib.getExe' pkgs.gopls "gopls";
          languages.go = "go";
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
          languages.templ = "templ";
        };

        ty = {
          command = lib.getExe' pkgs.ty "ty";
          args = [ "server" ];
          languages.py = "python";
        };

        rust_analyzer = {
          command = lib.getExe' pkgs.rust-analyzer "rust-analyzer";
          languages.rs = "rust";
        };

        lua_ls = {
          command = lib.getExe' pkgs.lua-language-server "lua-language-server";
          languages.lua = "lua";
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
          languages = {
            sh = "shellscript";
            bash = "shellscript";
            zsh = "shellscript";
          };
        };

        jsonls = {
          command = vscodeLs "vscode-json-language-server";
          args = [ "--stdio" ];
          languages = {
            json = "json";
            jsonc = "jsonc";
          };
          initOptions.provideFormatter = false;
        };

        cssls = {
          command = vscodeLs "vscode-css-language-server";
          args = [ "--stdio" ];
          languages = {
            css = "css";
            scss = "scss";
            less = "less";
          };
          initOptions.provideFormatter = false;
          settings = {
            css.validate = true;
            scss.validate = true;
          };
        };

        yamlls = {
          command = lib.getExe' pkgs.yaml-language-server "yaml-language-server";
          args = [ "--stdio" ];
          languages = {
            yaml = "yaml";
            yml = "yaml";
          };
          settings.yaml.keyOrdering = false;
        };

        taplo = {
          command = lib.getExe' pkgs.taplo "taplo";
          args = [
            "lsp"
            "stdio"
          ];
          languages.toml = "toml";
        };

        sqruff = {
          command = lib.getExe' pkgs.sqruff "sqruff";
          args = [ "lsp" ];
          languages.sql = "sql";
        };
      };

      # Claude Code's .lsp.json: settings keep their names, initialization
      # options become initializationOptions, and language ids are keyed on
      # dotted extensions.
      toClaude =
        _: s:
        {
          inherit (s) command;
        }
        // lib.optionalAttrs (s ? args) { inherit (s) args; }
        // {
          extensionToLanguage = lib.mapAttrs' (ext: lang: lib.nameValuePair ".${ext}" lang) s.languages;
        }
        // lib.optionalAttrs (s ? settings) { inherit (s) settings; }
        // lib.optionalAttrs (s ? initOptions) { initializationOptions = s.initOptions; };

      # crush's `lsp` map: filetypes match as ".<ext>" suffixes on the file
      # name, and the settings move to `options`. Commands must be store paths:
      # user-configured servers skip crush's PATH probe, and crush runs without
      # nvim's wrapper PATH to find binaries by name.
      toCrush =
        _: s:
        {
          inherit (s) command;
        }
        // lib.optionalAttrs (s ? args) { inherit (s) args; }
        // {
          filetypes = builtins.attrNames s.languages;
        }
        // lib.optionalAttrs (s ? settings) { options = s.settings; }
        // lib.optionalAttrs (s ? initOptions) { init_options = s.initOptions; };
    in
    {
      options.stubbe.lsp.clients = lib.mkOption {
        type = lib.types.raw;
        internal = true;
        description = "Per-agent renderings of the language server inventory: `claude` (.lsp.json plugin) and `crush` (lsp map).";
      };

      config.stubbe.lsp.clients =
        # Rendered only for CLIs that are actually enabled -- and it keeps
        # `config` in an expression, which deadnix requires to see it used.
        lib.optionalAttrs config.features.claudeCode { claude = lib.mapAttrs toClaude servers; }
        // lib.optionalAttrs config.features.crush { crush = lib.mapAttrs toCrush servers; };
    };
}
