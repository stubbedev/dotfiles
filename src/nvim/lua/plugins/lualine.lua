return {
  {
    "nvim-lualine/lualine.nvim",
    dependencies = {
      { "catppuccin/nvim" },
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
                  "buffers",
                  show_filename_only = true,
                  hide_filename_extension = false,
                  show_modified_status = true,
                  mode = 0,
                  max_length = vim.o.columns,
                  filetype_names = { snacks_dashboard = "" },
                  use_mode_colors = true,
                  symbols = {
                    modified = " ●",
                    alternate_file = "^",
                    directory = "",
                  },
                },
              },
            }
          end

          -- lualine.setup() is a full re-init (~3ms), so only run it when the
          -- tabline actually has to appear or disappear -- i.e. when the
          -- listed-buffer count crosses the 2-buffer threshold get_tabline()
          -- keys on. Opening a picker adds buffers in bursts; without this
          -- guard each one paid for a re-init that rendered the same tabline.
          local tabline_shown = nil
          local function update_lualine_tabline()
            local lualine = require("lualine")
            local tabline = get_tabline()
            local shown = tabline ~= nil
            if shown == tabline_shown then
              return
            end
            tabline_shown = shown
            local config = lualine.get_config()
            config.tabline = tabline
            lualine.setup(config)
          end

          vim.api.nvim_create_autocmd({ "BufAdd", "BufDelete", "BufWipeout" }, {
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
            "filename",
            file_status = false,
            newfile_status = false,
            path = 1,
            shorting_target = 40,
            symbols = {
              modified = "",
              readonly = "",
              unnamed = "",
              newfile = "",
            },
          })
          local lualineC = {}
          require("lualine").setup({
            sections = {
              lualine_c = lualineC,
              lualine_x = lualineX,
              lualine_y = lualineY,
              lualine_z = lualineZ,
            },
            tabline = get_tabline(),
          })
        end,
      },
    },
    lazy = false,
    config = function()
      require("lualine").setup({
        options = {
          theme = "catppuccin-mocha",
          extensions = { "lazy", "oil", "nvim-dap", "trouble" },
        },
      })
    end,
  },
}
