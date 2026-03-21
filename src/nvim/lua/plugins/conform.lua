return {
  "stevearc/conform.nvim",
  opts_extend = { "formatters_by_ft" },
  opts = {
    formatters_by_ft = {
      -- html/xml/markdown: oxfmt is workspace-gated and unreliable for standalone files
      html = { "prettier" },
      xml = { "prettier" },
      markdown = { "prettier" },
      -- js/ts/json/css/scss: handled by oxfmt LSP
      php = { "pint" },
    },
  },
}
