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
          local lualineX = require("lualine").get_config().sections.lualine_x or {}
          table.insert(lualineZ, { require("recorder").recordingStatus })
          table.insert(lualineY, { require("recorder").displaySlots })
          table.insert(lualineX, 1, {
            'filename',
            file_status = true,
            newfile_status = false,
            path = 1,
            shorting_target = 40,
            symbols = {
              modified = '[+]',
              readonly = '',
              unnamed = '',
              newfile = '',
            }
          })
          local lualineC = {
            {
              'buffers',
              show_filename_only = true,       -- Shows shortened relative path when set to false.
              hide_filename_extension = false, -- Hide filename extension when set to true.
              show_modified_status = true,     -- Shows indicator when the buffer is modified.
              mode = 0,                        -- 0: Shows buffer name
              -- 1: Shows buffer index
              -- 2: Shows buffer name + buffer index
              -- 3: Shows buffer number
              -- 4: Shows buffer name + buffer number

              max_length = vim.o.columns * 2 / 3, -- Maximum width of buffers component,
              -- it can also be a function that returns
              -- the value of `max_length` dynamically.
              filetype_names = {
                snacks_dashboard = '',
              }, -- Shows specific buffer name for that filetype ( { `filetype` = `buffer_name`, ... } )

              -- Automatically updates active buffer color to match color of other components (will be overidden if buffers_color is set)
              use_mode_colors = true,

              buffers_color = {
                -- Same values as the general color option can be used here.
                active = 'lualine_c_normal',     -- Color for active buffer.
                inactive = 'lualine_c_inactive', -- Color for inactive buffer.
              },

              symbols = {
                modified = ' ●', -- Text to show when the buffer is modified
                alternate_file = '^', -- Text to show to identify the alternate file
                directory = '', -- Text to show when the buffer is a directory
              },
            }
          }
          require("lualine").setup({
            sections = {
              lualine_c = lualineC,
              lualine_x = lualineX,
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
          extensions = { "lazy", "mason", "oil", "nvim-dap", "overseer", "trouble" },
        },
      })
    end,
  },
}
