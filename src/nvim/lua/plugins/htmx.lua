return {
  {
    "ThePrimeagen/htmx-lsp",
    event = "VeryLazy",
    config = function()
      require("lspconfig").htmx.setup({})
    end,
  },
}
