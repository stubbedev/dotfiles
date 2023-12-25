return {
  {
    'nvim-telescope/telescope.nvim',
    tag = '0.1.5',
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
          require("telescope").setup({
            extensions = {
              fzf = {
                fuzzy = true,
                override_generic_sorter = true,
                override_file_sorter = true,
                case_mode = "smart_case",
              }
            }
          })
          require("telescope").load_extension("fzf")
        end
      }
    },
    keys = {
      { "<leader><leader>", "<cmd>Telescope resume<cr>",                    desc = "Find resume." },
      { "<leader>ff",       "<cmd>Telescope find_files<cr>",                desc = "Find files." },
      { "<leader>fe",       "<cmd>Telescope grep_string<cr>",               desc = "Find selected word." },
      { "<leader>/",        "<cmd>Telescope current_buffer_fuzzy_find<cr>", desc = "Find in current buffer." },
      { "<leader>fw",       "<cmd>Telescope live_grep<cr>",                 desc = "Find word." },
      { "<leader>fb",       "<cmd>Telescope buffers<cr>",                   desc = "Find buffers." },
      { "<leader>f,",       "<cmd>Telescope buffers<cr>",                   desc = "Find buffers." },
      { "<leader>fh",       "<cmd>Telescope help_tags<cr>",                 desc = "Find help_tags." },
      { "<leader>fs",       "<cmd>Telescope lsp_document_symbols<cr>",      desc = "Find symbols." },
      { "<leader>ft",       "<cmd>Telescope keymaps<cr>",                   desc = "Find keymaps." },
      { "<leader>fc",       "<cmd>Telescope commands<cr>",                  desc = "Find commands." },
      { "<leader>fm",       "<cmd>Telescope marks<cr>",                     desc = "Find marks." },
      { "<leader>fz",       "<cmd>Telescope colorscheme<cr>",               desc = "Find colorschemes." },
      { "<leader>fg",       "<cmd>Telescope git_status<cr>",                desc = "Find git status." },
      { "<leader>fv",       "<cmd>Telescope git_branches<cr>",              desc = "Find git branches." },
      { "<leader>fo",       "<cmd>Telescope oldfiles<cr>",                  desc = "Find oldfiles." },
    },
    opts = {}
  }
}
