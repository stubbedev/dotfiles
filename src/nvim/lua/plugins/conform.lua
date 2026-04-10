return {
  "stevearc/conform.nvim",
  opts_extend = { "formatters_by_ft" },
  opts = function(_, opts)
    opts.formatters_by_ft = opts.formatters_by_ft or {}
    -- html/xml/markdown/vue: prettier with ~/.prettierrc.json
    opts.formatters_by_ft.html = { "prettier" }
    opts.formatters_by_ft.xml = { "prettier" }
    opts.formatters_by_ft.markdown = { "prettier" }
    opts.formatters_by_ft.vue = { "prettier" }
    -- js/ts/json/css/scss: handled by oxfmt LSP
    opts.formatters_by_ft.php = { "pint" }
    opts.formatters_by_ft.caddy = { "caddy" }

    opts.formatters = opts.formatters or {}
    opts.formatters.prettier = vim.tbl_extend("force", opts.formatters.prettier or {}, {
      command = vim.fn.expand("~/.bun/bin/prettier"),
    })
    opts.formatters.caddy = { command = "caddy", args = { "fmt", "-" }, stdin = true }

    return opts
  end,
}
