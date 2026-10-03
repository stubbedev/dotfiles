# The language server inventory for Harness's `lsp` config block: one list
# of servers, one renderer.
_: {
  flake.modules.homeManager.lspClients =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      # Neutral shape per server: `languages` maps a file extension (sans dot)
      # to the LSP language id -- every consumer needs both halves, claude as
      # extensionToLanguage, harness as filetypes (extensions match by suffix).
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

        superhtml = {
          command = lib.getExe' pkgs.superhtml "superhtml";
          args = [ "lsp" ];
          languages.html = "html";
        };

        biome = {
          command = lib.getExe' pkgs.biome "biome";
          args = [ "lsp-proxy" ];
          languages = {
            css = "css";
            json = "json";
            jsonc = "jsonc";
          };
        };

        yayamlls = {
          command = lib.getExe' pkgs.yayamlls "yayamlls";
          languages = {
            yaml = "yaml";
            yml = "yaml";
          };
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

      # harness's `lsp` map: filetypes match as ".<ext>" suffixes on the file
      # name, and the settings move to `options`. Commands must be store paths:
      # user-configured servers skip harness's PATH probe, and harness runs without
      # nvim's wrapper PATH to find binaries by name.
      toHarness =
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
        description = "Harness's `lsp` map, rendered from the shared inventory.";
      };

      config.stubbe.lsp.clients =
        # Keeps `config` in an expression, which deadnix requires to see used.
        lib.optionalAttrs config.features.harness { harness = lib.mapAttrs toHarness servers; };
    };
}
