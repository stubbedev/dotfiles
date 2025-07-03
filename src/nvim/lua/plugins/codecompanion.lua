return {
  {
    "olimorris/codecompanion.nvim",
    opts = {
      strategies = {
        chat = {
          adapter = "copilot",
        },
        inline = {
          adapter = "copilot",
        },
        cmd = {
          adapter = "copilot",
        }
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
        inline = {
          layout = "horizontal",
        }
      },
    },
    keys = {
      { "<leader>aa", "<cmd>CodeCompanionChat Toggle<cr>", desc = "CodeCompanion Toggle Chat", mode = { "n", "v" } },
      { "<leader>ae", "<cmd>CodeCompanionChat Add<cr>",    desc = "CodeCompanion Add Buffer",  mode = { "n", "v" } },
      { "<leader>ap", "<cmd>CodeCompanionActions<cr>",     desc = "CodeCompanion Actions",     mode = { "n", "v" } },
      {
        "<leader>aq",
        function()
          vim.ui.input({ prompt = "CodeCompanion: " }, function(input)
            if input and input ~= "" then
              vim.cmd("CodeCompanion " .. input)
            end
          end)
        end,
        desc = "CodeCompanion (Prompt)",
        mode = { "n" }
      },
      {
        "<leader>aq",
        function()
          vim.ui.input({ prompt = "CodeCompanion: " }, function(input)
            if input and input ~= "" then
              vim.cmd("'<,'>CodeCompanion " .. input)
            end
          end)
        end,
        desc = "CodeCompanion (Prompt)",
        mode = { "v" }
      },
      {
        "<leader>ad",
        function()
          vim.ui.input({ prompt = "CodeCompanion Explain: " }, function(input)
            if input and input ~= "" then
              vim.cmd("CodeCompanion /explain " .. input)
            end
          end)
        end,
        desc = "CodeCompanion Explain (Prompt)",
        mode = { "n" }
      },
      {
        "<leader>ad",
        function()
          vim.ui.input({ prompt = "CodeCompanion Explain: " }, function(input)
            if input and input ~= "" then
              vim.cmd("'<,'>CodeCompanion /explain " .. input)
            end
          end)
        end,
        desc = "CodeCompanion Explain (Prompt)",
        mode = { "v" }
      },
      {
        "<leader>af",
        function()
          vim.ui.input({ prompt = "CodeCompanion Fix: " }, function(input)
            if input and input ~= "" then
              vim.cmd("CodeCompanion /fix " .. input)
            end
          end)
        end,
        desc = "CodeCompanion Fix (Prompt)",
        mode = { "n" }
      },
      {
        "<leader>af",
        function()
          vim.ui.input({ prompt = "CodeCompanion Fix: " }, function(input)
            if input and input ~= "" then
              vim.cmd("'<,'>CodeCompanion /fix " .. input)
            end
          end)
        end,
        desc = "CodeCompanion Fix (Prompt)",
        mode = { "v" }
      },
      {
        "<leader>al",
        function()
          vim.ui.input({ prompt = "CodeCompanion LSP: " }, function(input)
            if input and input ~= "" then
              vim.cmd("CodeCompanion /lsp " .. input)
            end
          end)
        end,
        desc = "CodeCompanion LSP (Prompt)",
        mode = { "n" }
      },
      {
        "<leader>al",
        function()
          vim.ui.input({ prompt = "CodeCompanion LSP: " }, function(input)
            if input and input ~= "" then
              vim.cmd("'<,'>CodeCompanion /lsp " .. input)
            end
          end)
        end,
        desc = "CodeCompanion LSP (Prompt)",
        mode = { "v" }
      },
      {
        "<leader>ab",
        function()
          vim.ui.input({ prompt = "CodeCompanion Buffer: " }, function(input)
            if input and input ~= "" then
              vim.cmd("CodeCompanion /buffer " .. input)
            end
          end)
        end,
        desc = "CodeCompanion Buffer (Prompt)",
        mode = { "n" }
      },
      {
        "<leader>ab",
        function()
          vim.ui.input({ prompt = "CodeCompanion Buffer: " }, function(input)
            if input and input ~= "" then
              vim.cmd("'<,'>CodeCompanion /buffer " .. input)
            end
          end)
        end,
        desc = "CodeCompanion Buffer (Prompt)",
        mode = { "v" }
      },
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
