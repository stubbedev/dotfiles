return {
  {
    "ThePrimeagen/htmx-lsp",
    event = "VeryLazy",
    config = function()
      require("nvim-lspconfig").htmx.setup({})
    end,
  },
}
