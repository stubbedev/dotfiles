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
          stages = 'static'
        }
      },
      {
        "ecthelionvi/NeoComposer.nvim",
        dependencies = { "kkharji/sqlite.lua" },
        opts = {
          keymaps = {
            toggle_macro_menu = "<c-q>"
          }
        }
      }
    },
    lazy = false,
    config = function ()
      require('lualine').setup({
        options = {
          theme = 'catppuccin',
          extensions = { "nvim-tree", "lazy", "mason" },
          sections = {
            lualine_c = { require('NeoComposer.ui').status_recording }
          }
        }
      })
    end
  },
  {
    'romgrk/barbar.nvim',
    dependencies = {
      'lewis6991/gitsigns.nvim',
      'nvim-tree/nvim-web-devicons',
    },
    init = function() vim.g.barbar_auto_setup = false end,
    opts = {},
  },
}
