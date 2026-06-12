{
  wlib,
  lib,
  pkgs,
  ...
}:
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
      # Core / always-on
      nixd
      lua-language-server
      vscode-langservers-extracted # html, cssls (handles scss), jsonls, eslint
      bash-language-server
      taplo
      yaml-language-server
      marksman
      dot-language-server

      # Web / JS / TS
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

      # Nix static analysis (statix wired via LazyVim's lang.nix nvim-lint
      # config; deadnix added explicitly in plugins/lint.lua).
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

      # `nix` CLI: required by nixd (flake eval) and by lsp.lua's
      # before_init callback that picks the right nixos/home config.
      nix

      # JS runtime for plugins that need node (copilot, blade ls, etc.)
      nodejs

      # ── DAP backends ────────────────────────────────────────
      delve
      python3Packages.debugpy
    ];
  };
}
