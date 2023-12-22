return {
  {
    'nvim-telescope/telescope.nvim', tag = '0.1.5',
    lazy = false,
    dependencies = {
      {
        "nvim-telescope/telescope-ui-select.nvim",
        config = function()
          require("telescope").setup({
            extensions = {
              ["ui-select"] = {
                require("telescope.themes").get_dropdown {}
              }
            }
          })
          require("telescope").load_extension("ui-select")
        end
      },
      {
        'nvim-lua/plenary.nvim',
      },
      {
        "nvim-telescope/telescope-fzf-native.nvim",
        build = "make",
        config = function()
          require("telescope").load_extension("fzf")
        end
      }
    },
    keys = {
      { "<leader>ff", "<cmd>Telescope find_files<cr>", desc = "Find files." },
      { "<leader>fe", "<cmd>Telescope grep_string<cr>", desc = "Find selected word." },
      { "<leader>/", "<cmd>Telescope current_buffer_fuzzy_find<cr>", desc = "Find in current buffer." },
      { "<leader>fw", "<cmd>Telescope live_grep<cr>", desc = "Find word." },
      { "<leader>fb", "<cmd>Telescope buffers<cr>", desc = "Find word." },
      { "<leader>fh", "<cmd>Telescope help_tags<cr>", desc = "Find word." },
      { "<leader>fs", "<cmd>Telescope treesitter<cr>", desc = "Find symbols." },
    },
    opts = {}
  }
}
