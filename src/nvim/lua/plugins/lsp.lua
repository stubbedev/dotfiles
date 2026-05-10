local nixd_eval_cache = {}

local function nixd_eval(root, attr, apply)
  local key = root .. "::" .. attr .. "::" .. (apply or "")
  if nixd_eval_cache[key] ~= nil then
    return nixd_eval_cache[key]
  end
  local cmd = { "nix", "eval", "--json", "--no-warn-dirty", root .. "#" .. attr }
  if apply then
    table.insert(cmd, "--apply")
    table.insert(cmd, apply)
  end
  local out = vim.fn.system(cmd)
  local result = nil
  if vim.v.shell_error == 0 then
    local ok, parsed = pcall(vim.json.decode, out)
    if ok then result = parsed end
  end
  nixd_eval_cache[key] = result
  return result
end

local function nixd_pick(root, attr, identity_attr)
  local names = nixd_eval(root, attr, "builtins.attrNames")
  if type(names) ~= "table" or #names == 0 then return nil end

  local map = nixd_eval(root, attr, "cs: builtins.mapAttrs (_: c: c." .. identity_attr .. ") cs")
  if type(map) == "table" then
    local hostname = vim.uv.os_gethostname()
    local user = vim.env.USER or ""
    for _, want in ipairs({ hostname, user .. "@" .. hostname, user }) do
      for name, ident in pairs(map) do
        if ident == want then return name end
      end
    end
  end

  local function looks_disposable(name)
    return name:match("[Ii]nstaller") or name:match("[Ii]so") or name:match("[Ll]ive")
  end
  local fallback
  for _, name in ipairs(names) do
    if not looks_disposable(name) then
      if fallback then return nil end
      fallback = name
    end
  end
  return fallback
end

local function nixd_settings_for_root(root)
  local settings = {
    nixpkgs = {
      expr = string.format(
        '(builtins.getFlake "%s").inputs.nixpkgs.legacyPackages.${builtins.currentSystem}',
        root
      ),
    },
    formatting = { command = { "nixfmt" } },
    options = {},
  }

  local nixos = nixd_pick(root, "nixosConfigurations", "config.networking.hostName")
  if nixos then
    settings.options.nixos = {
      expr = string.format(
        '(builtins.getFlake "%s").nixosConfigurations."%s".options',
        root, nixos
      ),
    }
  end

  local hm = nixd_pick(root, "homeConfigurations", "config.home.username")
  if hm then
    settings.options.home_manager = {
      expr = string.format(
        '(builtins.getFlake "%s").homeConfigurations."%s".options',
        root, hm
      ),
    }
  end

  return settings
end

return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      inlay_hints = { enabled = false },
      servers = {
        -- htmx-lsp binary is not installed; disable to suppress exit-code-127 warnings
        htmx = { enabled = false },
        -- nil_ls comes from lazyvim's nix extra; disable so only nixd attaches
        nil_ls = { enabled = false },
        nixd = {
          mason = false,
          settings = {
            nixd = {
              formatting = { command = { "nixfmt" } },
              nixpkgs = { expr = "import <nixpkgs> { }" },
            },
          },
          before_init = function(params, config)
            local root
            if params.workspaceFolders and params.workspaceFolders[1] then
              root = vim.uri_to_fname(params.workspaceFolders[1].uri)
            elseif params.rootUri then
              root = vim.uri_to_fname(params.rootUri)
            end
            if not root or vim.fn.filereadable(root .. "/flake.nix") == 0 then return end
            -- Mutate config.settings in place: vim.lsp.Client captures a reference at
            -- create() time, so reassigning the table here would be ignored.
            config.settings = config.settings or {}
            config.settings.nixd = vim.tbl_deep_extend(
              "force",
              config.settings.nixd or {},
              nixd_settings_for_root(root)
            )
          end,
        },
        oxlint = {
          filetypes = {
            "javascript",
            "javascriptreact",
            "typescript",
            "typescriptreact",
            "vue",
            "svelte",
            "astro",
          },
        },
        oxfmt = {
          filetypes = {
            "javascript",
            "javascriptreact",
            "typescript",
            "typescriptreact",
            "vue",
            "svelte",
            "astro",
            "json",
            "jsonc",
            "css",
            "scss",
          },
        },
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
        html = {
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
