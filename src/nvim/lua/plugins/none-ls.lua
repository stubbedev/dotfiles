return {
  {
    "jay-babu/mason-null-ls.nvim",
    event = { "BufReadPre", "BufNewFile" },
    lazy = false,
    dependencies = {
      { "williamboman/mason.nvim" },
      { "nvimtools/none-ls.nvim" },
    },
    config = function()
      local null_ls = require("null-ls")
      require("mason-null-ls").setup({
        automatic_installation = true,
        ensure_installed = {
          "stylua",
          "gitsigns",
          "spell",
          "luasnip",
          "tags",
          "gospel",
          "eslint",
          "php",
          "phpcs",
          "phpstan",
          "phpcbf",
          "phpcsfixer",
          "pylint",
          "ruff",
          "typos",
          "zsh",
          "alex",
          "dictionary",
          "autoflake",
          "goimports",
          "prettier",
          "rustfmt",
        },
      })

      null_ls.setup({
        sources = {
          null_ls.builtins.code_actions.gitsigns,
          null_ls.builtins.code_actions.shellcheck,
          null_ls.builtins.completion.spell,
          null_ls.builtins.completion.luasnip,
          null_ls.builtins.diagnostics.gospel,
          null_ls.builtins.diagnostics.luacheck,
          null_ls.builtins.diagnostics.eslint,
          null_ls.builtins.diagnostics.php,
          null_ls.builtins.diagnostics.phpcs,
          null_ls.builtins.diagnostics.phpstan,
          null_ls.builtins.diagnostics.pylint.with({
            diagnostics_postprocess = function(diagnostic)
              diagnostic.code = diagnostic.message_id
            end,
          }),
          null_ls.builtins.diagnostics.ruff,
          null_ls.builtins.diagnostics.typos,
          null_ls.builtins.diagnostics.zsh,
          null_ls.builtins.diagnostics.alex,
          null_ls.builtins.hover.dictionary,
          null_ls.builtins.formatting.stylua,
          null_ls.builtins.formatting.autoflake,
          null_ls.builtins.formatting.goimports,
          null_ls.builtins.formatting.phpcbf,
          null_ls.builtins.formatting.phpcsfixer,
          null_ls.builtins.formatting.prettier,
          null_ls.builtins.formatting.rustfmt,
        },
      })

      vim.keymap.set("n", "gf", function()
        vim.lsp.buf.format()
      end, { desc = "Format buffer null_ls" })
    end,
  },
}
