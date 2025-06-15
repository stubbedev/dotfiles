return {
  { "nvim-neo-tree/neo-tree.nvim", enabled = false },
  { "echasnovski/mini.indentscope", enabled = false },
  { "goolord/alpha-nvim", enabled = false },
  -- { "folke/persistence.nvim", enabled = false },
  { "folke/flash.nvim", enabled = false },
  { "folke/snacks.nvim", opts = {
    explorer = { enabled = false },
  } },
  {
    "neovim/nvim-lspconfig",
    opts = {
      inlay_hints = { enabled = false },
    },
  },
}
