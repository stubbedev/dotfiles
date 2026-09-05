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
        "cpp"
        "css"
        "desktop"
        "diff"
        "dockerfile"
        "editorconfig"
        "git_config"
        "git_rebase"
        "gitattributes"
        "gitcommit"
        "gitignore"
        "go"
        "gomod"
        "gotmpl"
        "gowork"
        "hcl"
        "html"
        "ini"
        "javascript"
        "jsdoc"
        "json"
        "just"
        "lua"
        "luadoc"
        "luap"
        "make"
        "markdown"
        "markdown_inline"
        "nix"
        "php"
        "php_only"
        "phpdoc"
        "printf"
        "python"
        "query"
        "regex"
        "rust"
        "scss"
        "sql"
        "ssh_config"
        "svelte"
        "templ"
        "terraform"
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
                vue-language-server
                vtsls
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
                clang-tools
                lemminx
                terraform-ls

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

                nix

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
