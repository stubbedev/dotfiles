return {
  {
    "mason-org/mason.nvim",
    opts = {
      ensure_installed = {
        "some-sass-language-server",
      },
    },
  },
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        somesass_ls = {
          filetypes = { "scss", "sass" },
        },
      },
    },
  },
}
