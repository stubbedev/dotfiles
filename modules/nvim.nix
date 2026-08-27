# Neovim, wrapped with its LSP/formatter/DAP toolchain from nixpkgs.
#
# The Lua tree stays a real, editable directory in the checkout (via
# `stubbe.mutable` link) rather than a store symlink: lazy.nvim writes
# lazy-lock.json and its plugin state next to it, and the whole point of the
# config is that an edit takes effect in the next nvim, not the next rebuild.
{ inputs, ... }:
{
  flake.modules.homeManager.nvim =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      nvim = inputs.wrappers.lib.evalPackage [
        { inherit pkgs; }
        (
          { wlib, ... }:
          {
            imports = [ wlib.wrapperModules.neovim ];

            config = {
              settings = {
                config_directory = lib.generators.mkLuaInline "vim.fn.stdpath('config')";
                aliases = [
                  "vi"
                  "vim"
                  "nano"
                  "ed"
                  "code"
                ];
              };

              runtimePkgs = with pkgs; [
                # ── LSPs ────────────────────────────────────────────────
                nixd
                lua-language-server
                vscode-langservers-extracted # html, cssls (scss), jsonls, eslint
                bash-language-server
                taplo
                yaml-language-server
                marksman
                dot-language-server

                # Web / JS / TS
                vtsls # LazyVim's default TS LSP (vim.g.lazyvim_ts_lsp = "vtsls")
                typescript-language-server
                oxlint
                oxfmt
                vue-language-server
                tailwindcss-language-server

                # Backend / domain
                phpantom_lsp
                templ
                basedpyright
                ruff
                rust-analyzer
                sqls
                gopls
                golangci-lint-langserver

                # Containers
                dockerfile-language-server
                docker-compose-language-service

                # ── Formatters / linters ────────────────────────────────
                stylua
                nixfmt
                prettier
                caddy
                gofumpt
                gotools # provides goimports
                golangci-lint
                hadolint
                markdownlint-cli2
                # Nix static analysis. statix is wired via LazyVim's lang.nix
                # nvim-lint config; deadnix is added explicitly in
                # src/nvim/lua/plugins/lint.lua.
                statix
                deadnix

                # ── Toolchain runtimes ──────────────────────────────────
                cargo
                rustc
                gomodifytags
                gotests
                impl
                iferr

                # Treesitter compile chain
                tree-sitter
                gcc

                # Search / IO used by snacks pickers, telescope, etc.
                ripgrep
                fd
                git

                # The `nix` CLI: needed by nixd (flake eval) and by lsp.lua's
                # before_init callback that picks the right nixos/home config.
                nix

                # JS runtime for plugins that need node (copilot, blade ls, …).
                nodejs

                # ── DAP backends ────────────────────────────────────────
                delve
                python3Packages.debugpy
              ];
            };
          }
        )
      ];
    in
    lib.mkIf config.features.desktop {
      home.packages = [ nvim ];
      home.sessionVariables = {
        EDITOR = lib.getExe nvim;
        VISUAL = lib.getExe nvim;
      };
      stubbe.mutable.".config/nvim".src = "nvim";
    };
}
