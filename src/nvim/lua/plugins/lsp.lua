return {
  {
    "neovim/nvim-lspconfig",
    opt_extend = { "servers", "inlay_hints" },
    opts = {
      inlay_hints = { enabled = false },
      servers = {
        lua_ls = {
          settings = {
            Lua = {
              runtime = {
                version = "LuaJIT"
              },
              diagnostics = {
                globals = { "vim" }
              },
              workspace = {
                checkThirdParty = false,
                library = {
                  vim.env.VIMRUNTIME,
                  "${3rd}/luv/library",
                  "${3rd}/busted/library",
                  vim.env.VIMRUNTIME .. "/lua"
                }
              }
            }
          }
        },
        htmx = {
          filetypes = { "html", "htm", "templ", "tmpl", "php", "blade", "twig" },
        },
        templ = {
          filetypes = { "templ" },
          settings = {
            templ = {
              enable_snippets = true,
            },
          },
        },
        bashls = {
          filetypes = { "sh", "zsh" },
        },
        tsserver = {
          lint = {
            project = true,
          },
        },
        taplo = {
          filetypes = { "toml" },
        },
        intelephense = {
          settings = {
            php = {
              validate = {
                enable = true,
              },
            },
            intelephense = {
              init_options = {
                clearCache = true,
              },
              stubs = {
                "phpcore",
                "laravel",
                "Illuminate",
                "Symfony",
                "wordpress",
                "woocommerce",
                "acf-pro",
                "apache",
                "bcmath",
                "bz2",
                "calendar",
                "com_dotnet",
                "Core",
                "csprng",
                "ctype",
                "curl",
                "date",
                "dba",
                "dom",
                "enchant",
                "exif",
                "fileinfo",
                "filter",
                "fpm",
                "ftp",
                "gd",
                "hash",
                "iconv",
                "imap",
                "interbase",
                "intl",
                "json",
                "ldap",
                "libxml",
                "mbstring",
                "mcrypt",
                "mssql",
                "mysql",
                "mysqli",
                "oci8",
                "odcb",
                "openssl",
                "password",
                "pcntl",
                "pcre",
                "PDO",
                "pdo_ibm",
                "pdo_mysql",
                "pdo_pgsql",
                "pdo_sqlite",
                "pgsql",
                "Phar",
                "posix",
                "pspell",
                "readline",
                "recode",
                "Reflection",
                "regex",
                "session",
                "shmop",
                "SimpleXML",
                "snmp",
                "soap",
                "sockets",
                "sodium",
                "SPL",
                "sqlite3",
                "standard",
                "superglobals",
                "sybase",
                "sysvmsg",
                "sysvsem",
                "sysvshm",
                "tidy",
                "tokenizer",
                "wddx",
                "xml",
                "xmlreader",
                "xmlrpc",
                "xmlwriter",
                "Zend OPcache",
                "zip",
                "zlib"
              },
              environment = {
                includePaths = {
                  '~/.config/composer/vendor/php-stubs/acf-pro-stubs/',
                  '~/.config/composer/vendor/php-stubs/woocommerce-stubs/',
                  '~/.config/composer/vendor/php-stubs/wordpress-stubs/',
                }
              },
              files = {
                maxSize = 500000000,
                exclude = {
                  "**/.git/**",
                  "**/.svn/**",
                  "**/.hg/**",
                  "**/.DS_Store/**",
                  "**/node_modules/**",
                  "**/bower_components/**",
                  "**/vendor/**/{Tests,tests}/**",
                },
              },
            },
          },
        }
      },
    },
  },
}
