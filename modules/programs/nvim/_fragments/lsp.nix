{ pkgs, lib, inputs, ... }:
let
  intelephenseStubs = [
    "phpcore"
    "laravel"
    "Illuminate"
    "Symfony"
    "wordpress"
    "woocommerce"
    "acf-pro"
    "apache"
    "bcmath"
    "bz2"
    "calendar"
    "com_dotnet"
    "Core"
    "csprng"
    "ctype"
    "curl"
    "date"
    "dba"
    "dom"
    "enchant"
    "exif"
    "fileinfo"
    "filter"
    "fpm"
    "ftp"
    "gd"
    "hash"
    "iconv"
    "imap"
    "interbase"
    "intl"
    "json"
    "ldap"
    "libxml"
    "mbstring"
    "mcrypt"
    "mssql"
    "mysql"
    "mysqli"
    "oci8"
    "odcb"
    "openssl"
    "password"
    "pcntl"
    "pcre"
    "PDO"
    "pdo_ibm"
    "pdo_mysql"
    "pdo_pgsql"
    "pdo_sqlite"
    "pgsql"
    "Phar"
    "posix"
    "pspell"
    "readline"
    "recode"
    "Reflection"
    "regex"
    "session"
    "shmop"
    "SimpleXML"
    "snmp"
    "soap"
    "sockets"
    "sodium"
    "SPL"
    "sqlite3"
    "standard"
    "superglobals"
    "sybase"
    "sysvmsg"
    "sysvsem"
    "sysvshm"
    "tidy"
    "tokenizer"
    "wddx"
    "xml"
    "xmlreader"
    "xmlrpc"
    "xmlwriter"
    "Zend OPcache"
    "zip"
    "zlib"
  ];

  nixpkgsPath = inputs.nixpkgs.outPath;
  hmPath = inputs.home-manager.outPath;

  # Evaluate just the option tree — fast, hostname-independent, no impure-eval risk.
  # See https://kokada.dev/blog/make-nixd-module-completion-to-work-anywhere-with-flakes/
  nixosOptionsExpr = ''
    (let
      pkgs = import "${nixpkgsPath}" { };
    in (pkgs.lib.evalModules {
      modules = (import "${nixpkgsPath}/nixos/modules/module-list.nix") ++
        [ ({ ... }: { nixpkgs.hostPlatform = builtins.currentSystem; }) ];
    })).options
  '';

  homeManagerOptionsExpr = ''
    (let
      pkgs = import "${nixpkgsPath}" { };
    in (pkgs.lib.evalModules {
      modules = [ "${hmPath}/modules/modules.nix" ];
      specialArgs = { inherit pkgs; check = false; };
    })).options
  '';
in
{
  plugins.lsp = {
    enable = true;
    inlayHints = false;
    servers = {
      nixd = {
        enable = true;
        package = pkgs.nixd;
        settings = {
          formatting.command = [ "nixfmt" ];
          nixpkgs.expr = "import ${nixpkgsPath} { }";
          diagnostic.suppress = [ "sema-escaping-with" ];
          options = {
            nixos.expr = nixosOptionsExpr;
            home_manager.expr = homeManagerOptionsExpr;
          };
        };
      };

      lua_ls = {
        enable = true;
        package = pkgs.lua-language-server;
        settings = {
          Lua = {
            runtime.version = "LuaJIT";
            diagnostics.globals = [ "vim" ];
            workspace = {
              checkThirdParty = false;
              library.__raw = ''
                {
                  vim.env.VIMRUNTIME,
                  "''${3rd}/luv/library",
                  "''${3rd}/busted/library",
                  vim.env.VIMRUNTIME .. "/lua",
                }
              '';
            };
          };
        };
      };

      html = {
        enable = true;
        package = pkgs.vscode-langservers-extracted;
        filetypes = [
          "html"
          "htm"
          "templ"
          "tmpl"
          "twig"
        ];
      };

      templ = {
        enable = true;
        package = pkgs.templ;
        filetypes = [ "templ" ];
        settings.templ.enable_snippets = true;
      };

      bashls = {
        enable = true;
        package = pkgs.bash-language-server;
        filetypes = [
          "sh"
          "zsh"
        ];
      };

      taplo = {
        enable = true;
        package = pkgs.taplo;
        filetypes = [ "toml" ];
      };

      ts_ls = {
        enable = true;
        package = pkgs.typescript-language-server;
        settings.lint.project = true;
      };

      oxlint = {
        enable = true;
        package = pkgs.oxlint;
        filetypes = [
          "javascript"
          "javascriptreact"
          "typescript"
          "typescriptreact"
          "vue"
          "svelte"
          "astro"
        ];
      };

      intelephense = {
        enable = true;
        package = pkgs.intelephense;
        settings = {
          php.validate.enable = true;
          intelephense = {
            init_options.clearCache = true;
            stubs = intelephenseStubs;
            environment.includePaths = [
              "~/.config/composer/vendor/php-stubs/acf-pro-stubs/"
              "~/.config/composer/vendor/php-stubs/woocommerce-stubs/"
              "~/.config/composer/vendor/php-stubs/wordpress-stubs/"
            ];
            files = {
              maxSize = 500000000;
              exclude = [
                "**/.git/**"
                "**/.svn/**"
                "**/.hg/**"
                "**/.DS_Store/**"
                "**/node_modules/**"
                "**/bower_components/**"
                "**/vendor/**/{Tests,tests}/**"
              ];
            };
          };
        };
      };

      volar = {
        enable = true;
        package = pkgs.vue-language-server;
        filetypes = [ "vue" ];
        extraOptions.init_options.vue.hybridMode = false;
      };

      cssls = {
        enable = true;
        package = pkgs.vscode-langservers-extracted;
        filetypes = [
          "css"
          "scss"
          "less"
          "sass"
        ];
      };

      jsonls = {
        enable = true;
        package = pkgs.vscode-langservers-extracted;
      };

      yamlls = {
        enable = true;
        package = pkgs.yaml-language-server;
      };

      tailwindcss = {
        enable = true;
        package = pkgs.tailwindcss-language-server;
        filetypes = [
          "astro"
          "blade"
          "css"
          "html"
          "javascript"
          "javascriptreact"
          "less"
          "markdown"
          "mdx"
          "postcss"
          "sass"
          "scss"
          "svelte"
          "templ"
          "twig"
          "typescript"
          "typescriptreact"
          "vue"
        ];
      };
    };
  };

  extraPackages = [
    pkgs.oxfmt
  ];
  extraConfigLuaPost = ''
    -- oxfmt as a custom LSP server (not yet in lspconfig defaults).
    local oxfmt_cmd = "${lib.getExe pkgs.oxfmt}"
    if vim.fn.executable(oxfmt_cmd) == 1 then
      vim.lsp.config("oxfmt", {
        cmd = { oxfmt_cmd, "--lsp" },
        filetypes = {
          "javascript", "javascriptreact",
          "typescript", "typescriptreact",
          "vue", "svelte", "astro",
          "json", "jsonc", "css", "scss",
        },
        root_markers = { ".git", "package.json" },
      })
      vim.lsp.enable("oxfmt")
    end
  '';
}
