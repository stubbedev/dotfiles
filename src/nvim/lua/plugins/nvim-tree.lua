return {
  {
    "nvim-tree/nvim-tree.lua",
    dependencies = {
      { "nvim-tree/nvim-web-devicons" },
      {
        'akinsho/bufferline.nvim',
        version = "*",
        opts = {}
      }
    },
    opts = {
      disable_netrw = true
    },
    keys = {
      { "<leader>e", "<cmd>NvimTreeToggle<cr>", desc = "Toggle file tree." }
    }
  }
}
