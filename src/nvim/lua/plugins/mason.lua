return {
  {
    "williamboman/mason.nvim",
    event = "LazyFile",
    cmd = "Mason",
    keys = { { "<leader>cm", "<cmd>Mason<cr>", desc = "Mason" } },
    build = ":MasonUpdate",
    opts_extend = { "ensure_installed" },
    opts = {
      ensure_installed = {
        "templ",
        "intelephense",
        "htmx-lsp"
      },
    },
  },
}
