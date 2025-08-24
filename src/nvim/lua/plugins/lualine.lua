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

          local function get_tabline()
            local buffers = vim.tbl_filter(function(bufnr)
              return vim.api.nvim_buf_is_loaded(bufnr) and (vim.fn.buflisted(bufnr) == 1)
            end, vim.api.nvim_list_bufs())
            if #buffers < 2 then
              return nil
            end
            return {
              lualine_a = {
                {
                  'buffers',
                  show_filename_only = true,
                  hide_filename_extension = false,
                  show_modified_status = true,
                  mode = 0,
                  max_length = vim.o.columns * 2 / 3,
                  filetype_names = { snacks_dashboard = '' },
                  use_mode_colors = true,
                  symbols = {
                    modified = ' ●',
                    alternate_file = '^',
                    directory = '',
                  },
                }
              },
            }
          end

          local function update_lualine_tabline()
            local lualine = require("lualine")
            local config = lualine.get_config()
            config.tabline = get_tabline()
            lualine.setup(config)
          end

          vim.api.nvim_create_autocmd({ "BufAdd", "BufDelete", "BufWipeout", "BufEnter" }, {
            callback = function()
              vim.schedule(function()
                pcall(update_lualine_tabline)
              end)
            end,
            nested = true,
          })

          local lualineZ = require("lualine").get_config().sections.lualine_z or {}
          local lualineY = require("lualine").get_config().sections.lualine_y or {}
          local lualineX = require("lualine").get_config().sections.lualine_x or {}
          table.insert(lualineZ, { require("recorder").recordingStatus })
          table.insert(lualineY, { require("recorder").displaySlots })
          table.insert(lualineX, 1, {
            'filename',
            file_status = false,
            newfile_status = false,
            path = 1,
            shorting_target = 40,
            symbols = {
              modified = '',
              readonly = '',
              unnamed = '',
              newfile = '',
            }
          })
          local lualineC = {}
          require("lualine").setup({
            sections = {
              lualine_c = lualineC,
              lualine_x = lualineX,
              lualine_y = lualineY,
              lualine_z = lualineZ,
            },
            tabline = get_tabline()
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
