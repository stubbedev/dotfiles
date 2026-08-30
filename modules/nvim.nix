# A real editable directory, not a store symlink: vim.pack writes plugin state
# next to it, and an edit must take effect in the next nvim, not the next
# rebuild.
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
      # From nix rather than `:TSInstall` compiling at runtime, which is why
      # runtimePkgs carries no gcc or tree-sitter CLI.
      # Parsers and queries must come from the SAME nvim-treesitter checkout or a
      # grammar drifts from the query written against it. nixpkgs'
      # independently-versioned `tree-sitter-grammars` does drift, and fails with
      # `Invalid node type "tool_directive"` (gomod), `keyword_include` (sql).
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

              # Same layout vim.pack uses, so nix-supplied runtime dirs and
              # vim.pack plugins coexist without either knowing about the other.
              specs.treesitter = treesitter-runtime;

              runtimePkgs = with pkgs; [
                nixd
                lua-language-server
                vscode-langservers-extracted # html, cssls (scss), jsonls, eslint
                bash-language-server
                taplo
                yaml-language-server
                marksman

                # tsgo has no tsserver *plugin* support, which is why vue and
                # svelte each run a self-contained server below.
                typescript-go
                oxlint
                oxfmt
                vue-language-server # v3 bridges to tsgo itself
                svelte-language-server

                phpantom_lsp
                templ
                ruff
                ty
                rust-analyzer
                gopls
                golangci-lint-langserver

                sqruff
                postgres-language-server # deeper postgres semantics when a project wants it

                docker-language-server

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
                statix
                deadnix

                cargo
                rustc
                gomodifytags
                gotests
                impl
                iferr

                ripgrep
                fd
                fzf
                git

                ast-grep

                # For the PR_SET_PDEATHSIG wrapper in src/nvim/lua/lsp.lua: some
                # servers ignore the LSP processId and outlive an unclean exit.
                util-linux

                # nixd shells out to it for flake eval.
                nix

                # Several of the servers above are still node programs.
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
