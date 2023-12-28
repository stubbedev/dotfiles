return {
  {
    "nvim-lualine/lualine.nvim",
    dependencies = {
      {
        "nvim-tree/nvim-web-devicons"
      },
      {
        'rcarriga/nvim-notify',
        opts = {
          render = 'compact',
          stages = 'fade',
          background_colour = 'transparent',
        }
      },
    },
    lazy = false,
    config = function()
      require('lualine').setup({
        options = {
          theme = 'catppuccin',
          extensions = { "nvim-tree", "lazy", "mason" },
        }
      })
    end
  },
}
