return {
  {
    "nvim-lualine/lualine.nvim",
    dependencies = {
      {
        "rcarriga/nvim-notify",
        opts = {
          render = "compact",
          stages = "static",
          background_colour = "transparent",
        },
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
          { "^^", desc = " Insert macro breakpoint" },
        },
        config = function()
          require("recorder").setup({
            slots = { "a", "b", "c" },
            dynamicSlots = "rotate",
            mapping = {
              startStopRecording = "q",
              playMacro = "Q",
              switchSlot = "<C-q>",
              editMacro = "cq",
              deleteAllMacros = "dq",
              yankMacro = "yq",
              addBreakPoint = "^^",
            },
            clear = false,
            logLevel = vim.log.levels.INFO,
            lessNotifications = true,
            useNerdfontIcons = true,
            performanceOpts = {
              countThreshold = 100,
              lazyredraw = true,
              noSystemClipboard = true,
              autocmdEventsIgnore = {
                "TextChangedI",
                "TextChanged",
                "InsertLeave",
                "InsertEnter",
                "InsertCharPre",
              },
            },
            dapSharedKeymaps = false,
            timeout = 300,
          })

          local lualineZ = require("lualine").get_config().sections.lualine_z or {}
          local lualineY = require("lualine").get_config().sections.lualine_y or {}
          table.insert(lualineZ, { require("recorder").recordingStatus })
          table.insert(lualineY, { require("recorder").displaySlots })

          require("lualine").setup({
            sections = {
              lualine_c = {
                {
                  "filename",
                  file_status = true, -- displays file status (readonly status, modified status)
                  path = 1, -- 0 = just filename, 1 = relative path, 2 = absolute path
                },
              },
              lualine_y = lualineY,
              lualine_z = lualineZ,
            },
          })
        end,
      },
    },
    lazy = false,
    config = function()
      require("lualine").setup({
        options = {
          theme = "catppuccin",
          extensions = { "lazy", "mason" },
        },
      })
    end,
  },
}
