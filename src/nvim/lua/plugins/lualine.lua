return {
  "nvim-lualine/lualine.nvim",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  lazy = false,
  opts = {
    theme = "palenight",
    extensions = { "nvim-tree", "lazy", "mason" },
  }
}
