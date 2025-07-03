return {
  {
    "olimorris/codecompanion.nvim",
    opts = {
      strategies = {
        chat = {
          adapter = "copilot",
        },
      },
      opts = {
        log_level = "DEBUG",
      },
      display = {
        action_palette = {
          width = 95,
          height = 10,
          prompt = "CodeCompanion Actions",
          provider = "snacks",
          opts = {
            show_default_actions = true,        -- Show the default actions in the action palette?
            show_default_prompt_library = true, -- Show the default prompt library in the action palette?
          },
        },
      },
    },
    keys = {
      { "<leader>aa", "<cmd>CodeCompanionChat Toggle<cr>", desc = "CodeCompanion Toggle Chat", mode = { "n", "v" } },
      { "<leader>ae", "<cmd>CodeCompanionChat Add<cr>",    desc = "CodeCompanion Add Buffer",  mode = { "n", "v" } },
      { "<leader>ap", "<cmd>CodeCompanionActions<cr>",     desc = "CodeCompanion Actions",     mode = { "n", "v" } },
      { "<leader>aq", "<cmd>CodeCompanion<cr>",            desc = "CodeCompanion Prompt",      mode = { "n", "v" } },
      { "<leader>ad", "<cmd>CodeCompanion /explain<cr>",   desc = "CodeCompanion Explain",     mode = { "n", "v" } },
      { "<leader>af", "<cmd>CodeCompanion /fix<cr>",       desc = "CodeCompanion Fix",         mode = { "n", "v" } },
      { "<leader>al", "<cmd>CodeCompanion /lsp<cr>",       desc = "CodeCompanion LSP",         mode = { "n", "v" } },
    },
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
      "folke/snacks.nvim",
    },
  },
  {
    "MeanderingProgrammer/render-markdown.nvim",
    ft = { "markdown", "codecompanion" }
  },
  {
    "HakonHarnes/img-clip.nvim",
    opts = {
      filetypes = {
        codecompanion = {
          prompt_for_file_name = false,
          template = "[Image]($FILE_PATH)",
          use_absolute_path = true,
        },
      },
    },
  },
}
