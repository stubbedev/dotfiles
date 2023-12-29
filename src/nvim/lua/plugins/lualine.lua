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
      {
        "chrisgrieser/nvim-recorder",
        dependencies = "rcarriga/nvim-notify",
        keys = {
          -- these must match the keys in the mapping config below
          { "q", desc = "◉ Toggle Recording" },
          { "Q", desc = " Play Recording" },
          { "<C-q>", desc = "⊷ Switch macro slot" },
          { "cq", desc = "⧂ Edit macro" },
          { "dq", desc = "⨂ Delete all macros" },
          { "yq", desc = "⚇ Yank macro" },
        },
        config = function()
          require("recorder").setup({
            slots = { "a", "b", "c" },
            mapping = {
              startStopRecording = "q",
              playMacro = "Q",
              switchSlot = "<C-q>",
              editMacro = "cq",
              deleteAllMacros = "dq",
              yankMacro = "yq",
            },
          })

          local lualineZ = require("lualine").get_config().sections.lualine_z or {}
          local lualineY = require("lualine").get_config().sections.lualine_y or {}
          table.insert(lualineZ, { require("recorder").recordingStatus })
          table.insert(lualineY, { require("recorder").displaySlots })

          require("lualine").setup {
            sections = {
              lualine_y = lualineY,
              lualine_z = lualineZ,
            },
          }
        end,
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
