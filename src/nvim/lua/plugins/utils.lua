return {
  {
    "aserowy/tmux.nvim",
    opts = {}
  },
  {
    'windwp/nvim-autopairs',
    event = "InsertEnter",
    opts = {
      disable_filetype = { "TelescopePrompt", "vim" },
    }
  },
  {
    'HiPhish/rainbow-delimiters.nvim',
    config = function()
      local rainbow_delimiters = require('rainbow-delimiters')
      require('rainbow-delimiters.setup').setup({
        strategy = {
          [''] = rainbow_delimiters.strategy['global'],
          vim = rainbow_delimiters.strategy['local'],
        },
        query = {
          [''] = 'rainbow-delimiters',
          lua = 'rainbow-blocks',
        },
        priority = {
          [''] = 110,
          lua = 210,
        },
        highlight = {
          'RainbowDelimiterRed',
          'RainbowDelimiterYellow',
          'RainbowDelimiterBlue',
          'RainbowDelimiterOrange',
          'RainbowDelimiterGreen',
          'RainbowDelimiterViolet',
          'RainbowDelimiterCyan',
        },
      })
    end
  },
  {
    'echasnovski/mini.comment',
    version = '*',
    opts = {
      options = {
        ignore_blank_line = true,
        start_of_line = false,
        pad_comment_parts = true,
      },
    }
  },
  {
    "folke/noice.nvim",
    event = "VeryLazy",
    opts = {
      lsp = {
        -- override markdown rendering so that **cmp** and other plugins use **Treesitter**
        override = {
          ["vim.lsp.util.convert_input_to_markdown_lines"] = true,
          ["vim.lsp.util.stylize_markdown"] = true,
          ["cmp.entry.get_documentation"] = true,
        },
      },
      -- you can enable a preset for easier configuration
      presets = {
        bottom_search = true,         -- use a classic bottom cmdline for search
        command_palette = true,       -- position the cmdline and popupmenu together
        long_message_to_split = true, -- long messages will be sent to a split
        inc_rename = false,           -- enables an input dialog for inc-rename.nvim
        lsp_doc_border = false,       -- add a border to hover docs and signature help
      },                              -- add any options here
      routes = {
        {
          view = "notify",
          filter = { event = "msg_showmode" },
        },
      },
      views = {
        cmdline_popup = {
          position = {
            row = "40%",
            col = "50%",
          },
          size = {
            width = 60,
            height = "auto",
          },
        },
        popupmenu = {
          relative = "editor",
          position = {
            row = "50%",
            col = "50%",
          },
          size = {
            width = 60,
            height = 10,
          },
          border = {
            style = "none",
            padding = { 2, 3 },
          },
          win_options = {
            winhighlight = { Normal = "Normal", FloatBorder = "DiagnosticInfo" },
          },
        },
      },
    },
    dependencies = {
      -- if you lazy-load any plugin below, make sure to add proper `module="..."` entries
      "MunifTanjim/nui.nvim",
      -- OPTIONAL:
      --   `nvim-notify` is only needed, if you want to use the notification view.
      --   If not available, we use `mini` as the fallback
      "rcarriga/nvim-notify",
    }
  }
}
