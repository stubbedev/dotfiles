return {
  {
    "neovim/nvim-lspconfig",
    opt_extend = { "servers" },
    opts = {
      inlay_hints = { enabled = false },
      servers = {
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
              files = {
                maxSize = 5000000,
                stubs = {
                  "laravel",
                  "Illuminate",
                  "Symfony",
                },
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
