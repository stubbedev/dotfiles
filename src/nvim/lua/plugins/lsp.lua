return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        bashls = {
          filetypes = { "sh", "zsh" },
        },
        tsserver = {
          lint = {
            project = true,
          },
        },
      },
    },
  },
}
