{
  wlib,
  lib,
  pkgs,
  ...
}:
{
  imports = [ wlib.wrapperModules.neovim ];

  config.settings.config_directory =
    lib.generators.mkLuaInline "vim.fn.stdpath('config')";

  config.extraPackages = with pkgs; [
    # LSPs (mirrors the previous nixvim config)
    nixd
    lua-language-server
    vscode-langservers-extracted
    templ
    bash-language-server
    taplo
    typescript-language-server
    oxlint
    oxfmt
    intelephense
    vue-language-server
    yaml-language-server
    tailwindcss-language-server

    # Formatters
    stylua
    nixfmt
    prettier
    caddy

    # Treesitter compile chain
    tree-sitter
    gcc

    # Search / IO used by snacks pickers, telescope, etc.
    ripgrep
    fd
    git

    # JS runtime for plugins that need node (copilot, blade ls, etc.)
    nodejs

    # DAP backends
    delve
    python3Packages.debugpy
  ];
}
