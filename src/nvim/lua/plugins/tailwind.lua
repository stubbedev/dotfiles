return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        tailwindcss = {
          filetypes_exclude = { "php", "blade" },
        },
      },
    },
  },
}
