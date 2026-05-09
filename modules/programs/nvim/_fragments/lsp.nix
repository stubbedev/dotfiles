{ pkgs, lib, ... }:
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

  nixdBeforeInit = ''
    function(params, config)
      local root
      if params.workspaceFolders and params.workspaceFolders[1] then
        root = vim.uri_to_fname(params.workspaceFolders[1].uri)
      elseif params.rootUri then
        root = vim.uri_to_fname(params.rootUri)
      end
      if not root or vim.fn.filereadable(root .. "/flake.nix") == 0 then return end

      local hostname = vim.uv.os_gethostname()
      local user = vim.env.USER or ""

      local settings = {
        nixpkgs = {
          expr = string.format(
            '(builtins.getFlake "%s").inputs.nixpkgs.legacyPackages.''${builtins.currentSystem}',
            root
          ),
        },
        formatting = { command = { "nixfmt" } },
        options = {
          nixos = {
            expr = string.format(
              '(let f = builtins.getFlake "%s"; in f.nixosConfigurations.%s or f.nixosConfigurations.%s-nixos or {}).options or {}',
              root, hostname, user
            ),
          },
          home_manager = {
            expr = string.format(
              '(let f = builtins.getFlake "%s"; in f.homeConfigurations.%s or f.homeConfigurations.%s or {}).options or {}',
              root, user, hostname
            ),
          },
        },
      }

      config.settings = config.settings or {}
      config.settings.nixd = vim.tbl_deep_extend("force", config.settings.nixd or {}, settings)
    end
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
          formatting = { command = [ "nixfmt" ]; };
          nixpkgs = { expr = "import <nixpkgs> { }"; };
        };
        extraOptions = {
          before_init.__raw = nixdBeforeInit;
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
          "php"
          "blade"
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
          "aspnetcorerazor"
          "astro"
          "astro-markdown"
          "css"
          "django-html"
          "edge"
          "ejs"
          "eelixir"
          "elixir"
          "erb"
          "eruby"
          "gohtml"
          "gohtmltmpl"
          "haml"
          "handlebars"
          "hbs"
          "heex"
          "html"
          "htmlangular"
          "html-eex"
          "jade"
          "leaf"
          "less"
          "liquid"
          "markdown"
          "mdx"
          "mustache"
          "njk"
          "nunjucks"
          "postcss"
          "razor"
          "rust"
          "sass"
          "scss"
          "slim"
          "stylus"
          "sugarss"
          "surface"
          "svelte"
          "templ"
          "twig"
          "vue"
          "javascript"
          "javascriptreact"
          "reason"
          "rescript"
          "typescript"
          "typescriptreact"
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
