return {
  "stevearc/conform.nvim",
  opts_extend = { "formatters_by_ft" },
  opts = {
    formatters_by_ft = {
      css = { "prettier" },
      html = { "prettier" },
      xml = { "prettier" },
      javascript = { "prettier" },
      javascriptreact = { "prettier" },
      json = { "prettier" },
      jsonc = { "prettier" },
      markdown = { "prettier" },
      scss = { "prettier" },
      typescript = { "prettier" },
      typescriptreact = { "prettier" },
      php = { "pint" },
    },
  },
}
