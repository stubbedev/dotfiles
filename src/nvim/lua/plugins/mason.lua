return {
  {
    "mason-org/mason.nvim",
    version = "^1.0.0",
    event = "LazyFile",
    cmd = "Mason",
    keys = { { "<leader>cm", "<cmd>Mason<cr>", desc = "Mason" } },
    build = ":MasonUpdate",
    opts_extend = { "ensure_installed" },
    opts = {
      ensure_installed = {
        "templ",
        "intelephense",
        "htmx-lsp",
        "taplo"
      },
    },
  },
  {
    "mason-org/mason-lspconfig.nvim",
    version = "^1.0.0",
  }
}
