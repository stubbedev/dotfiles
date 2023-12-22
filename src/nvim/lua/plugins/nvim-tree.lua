return {
  {
    "nvim-tree/nvim-tree.lua",
    dependencies = {
      { "nvim-tree/nvim-web-devicons" },
      { 'akinsho/bufferline.nvim', version = "*" }
    },
    opts = {
      disable_netrw = true
    },
    keys = {
      { "<leader>n", "<cmd>NvimTreeToggle<cr>", desc = "Toggle file tree." }
    }
  }
}
