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

        shell_lsp = {
          command = lib.getExe pkgs.shell-lsp;
          languages = {
            sh = "sh";
            bash = "bash";
            bats = "bats";
            zsh = "zsh";
            ksh = "ksh";
            dash = "dash";
            mk = "makefile";
            mak = "makefile";
            just = "just";
            dockerfile = "dockerfile";
            containerfile = "dockerfile";
          };
          fileNames = [
            "makefile"
            "gnumakefile"
            "justfile"
          ];
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

      };

      # harness's `lsp` map: a filetype matches a file named "<filetype>" or
      # ending in ".<filetype>", and the settings move to `options`. Commands
      # must be store paths: user-configured servers skip harness's PATH probe,
      # and harness runs without nvim's wrapper PATH to find binaries by name.
      toHarness =
        _: s:
        {
          inherit (s) command;
        }
        // lib.optionalAttrs (s ? args) { inherit (s) args; }
        // {
          filetypes = builtins.attrNames s.languages ++ s.fileNames or [ ];
        }
        // lib.optionalAttrs (s ? settings) { options = s.settings; };

      # Claude's plugin `.lsp.json` dialect: extensions only, keyed with the
      # dot, so `fileNames` has no equivalent there.
      toClaude =
        _: s:
        {
          inherit (s) command;
          extensionToLanguage = lib.mapAttrs' (ext: lib.nameValuePair ".${ext}") s.languages;
        }
        // lib.optionalAttrs (s ? args) { inherit (s) args; };

      claudeServers = [ "shell_lsp" ];
    in
    {
      options.stubbe.lsp.clients = lib.mkOption {
        type = lib.types.raw;
        internal = true;
        description = "Harness's `lsp` map and Claude's `.lsp.json`, rendered from the shared inventory.";
      };

      config.stubbe.lsp.clients =
        lib.optionalAttrs config.features.harness { harness = lib.mapAttrs toHarness servers; }
        // lib.optionalAttrs config.features.claudeCode {
          claude = lib.mapAttrs toClaude (lib.getAttrs claudeServers servers);
        };
    };
}
