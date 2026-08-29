# Neovim, wrapped with its LSP/formatter/linter toolchain from nixpkgs.
#
# Three layers, each owning exactly one thing:
#   - this file: every *binary* (language servers, linters, formatters) and the
#     treesitter parsers, all pinned by flake.lock. Nothing is downloaded or
#     compiled at runtime, so there is no gcc or tree-sitter CLI here.
#   - src/nvim/init.lua: the editor plugins, via nvim 0.12's built-in
#     `vim.pack`. Those still come from GitHub, updated with `vim.pack.update()`.
#   - src/nvim/lua/*.lua: plain config. No plugin framework.
#
# The Lua tree stays a real, editable directory in the checkout (via
# `stubbe.mutable` link) rather than a store symlink: vim.pack writes its
# plugin state next to it, and the whole point of the config is that an edit
# takes effect in the next nvim, not the next rebuild.
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
      # Treesitter parsers and queries, from nix rather than `:TSInstall`
      # compiling them into ~/.local/share/nvim at runtime. That's why there is
      # no gcc or tree-sitter CLI in runtimePkgs.
      #
      # Both halves come from the same source. nixpkgs builds
      # `nvim-treesitter-parsers.<lang>` from the revisions nvim-treesitter
      # itself pins, and the queries below come from that same nvim-treesitter
      # checkout -- so a grammar can never drift from the query written against
      # it. Taking parsers from nixpkgs' independently-versioned
      # `tree-sitter-grammars` instead does drift, and it fails loudly:
      # `Invalid node type "tool_directive"` (gomod), `keyword_include` (sql).
      #
      # Updating is `nix flake update`; nothing here is pinned by hand.
      languages = [
        "bash"
        "blade"
        "c"
        "caddy"
        "comment"
        "css"
        "diff"
        "dockerfile"
        "git_rebase"
        "gitcommit"
        "go"
        "gomod"
        "gotmpl"
        "gowork"
        "hcl"
        "html"
        "javascript"
        "json"
        "just"
        "lua"
        "markdown"
        "markdown_inline"
        "nix"
        "php"
        "php_only"
        "phpdoc"
        "python"
        "query"
        "regex"
        "rust"
        "scss"
        "sql"
        "svelte"
        "templ"
        "toml"
        "tsx"
        "typescript"
        "vim"
        "vimdoc"
        "vue"
        "xml"
        "yaml"
      ];

      treesitter-runtime = pkgs.runCommand "nvim-treesitter-runtime" { } ''
        mkdir -p "$out/parser"
        ${lib.concatMapStringsSep "\n" (lang: ''
          ln -s ${pkgs.vimPlugins.nvim-treesitter-parsers.${lang}}/parser/${lang}.so "$out/parser/${lang}.so"
        '') languages}

        # src/nvim/after/queries/ still layers on top of these.
        ln -s ${pkgs.vimPlugins.nvim-treesitter}/runtime/queries "$out/queries"
      '';

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

              # The wrapper builds pack/myNeovimPackages/start and prepends it
              # to 'packpath' -- the same layout vim.pack uses, so nix-supplied
              # runtime dirs and vim.pack plugins coexist without either
              # knowing about the other.
              specs.treesitter = treesitter-runtime;

              runtimePkgs = with pkgs; [
                # ── LSPs ────────────────────────────────────────────────
                nixd
                lua-language-server
                vscode-langservers-extracted # html, cssls (scss), jsonls, eslint
                bash-language-server
                taplo
                yaml-language-server
                marksman

                # Web / JS / TS.
                #
                # typescript-go (`tsgo --lsp --stdio`) replaces vtsls and
                # typescript-language-server: one Go binary instead of a node
                # process plus three tsserver children. It has no tsserver
                # *plugin* support, which is why vue and svelte below each run
                # their own self-contained server rather than injecting a
                # plugin into a shared tsserver.
                typescript-go
                oxlint
                oxfmt
                vue-language-server # v3 bridges to tsgo itself
                svelte-language-server

                # Backend / domain
                phpantom_lsp
                templ
                basedpyright
                ruff
                rust-analyzer
                gopls
                golangci-lint-langserver

                # SQL: one Rust binary doing lint + format + LSP, with real
                # dialect support (postgres, sqlite, mysql, tsql, duckdb, ...).
                sqruff
                postgres-language-server # deeper postgres semantics when a project wants it

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
                shellcheck
                shfmt
                # Nix static analysis, wired in src/nvim/lua/format.lua.
                statix
                deadnix

                # ── Toolchain runtimes ──────────────────────────────────
                cargo
                rustc
                gomodifytags
                gotests
                impl
                iferr

                # Search / IO used by the picker and by git integration.
                ripgrep
                fd
                fzf
                git

                # Structural search-and-replace, driven by grug-far. Unlike
                # ripgrep it matches on syntax tree shape, so a project-wide
                # rename skips strings and comments that merely look the same.
                ast-grep

                # setpriv(1), for the PR_SET_PDEATHSIG wrapper that
                # src/nvim/lua/lsp.lua puts in front of every language server
                # so none of them survives an unclean nvim exit.
                util-linux

                # The `nix` CLI: needed by nixd (flake eval) and by lsp.lua's
                # before_init callback that picks the right nixos/home config.
                nix

                # JS runtime for the servers that are still node programs
                # (vue, svelte, the vscode-langservers-extracted family).
                nodejs
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
