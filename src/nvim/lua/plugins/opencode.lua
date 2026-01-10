return {
  {
    "NickvanDyke/opencode.nvim",
    dependencies = {
      { "folke/snacks.nvim", opts = { input = {}, picker = {}, terminal = {} } },
    },
    config = function()
      ---@type opencode.Opts
      vim.g.opencode_opts = {
        -- Configuration options here
      }

      -- Required for opts.events.reload
      vim.o.autoread = true
    end,
    keys = {
      { "<leader>aa", function() require("opencode").ask("@this: ", { submit = true }) end, desc = "OpenCode Ask", mode = { "n", "v" } },
      { "<leader>ae", function() require("opencode").select() end, desc = "OpenCode Select", mode = { "n", "v" } },
      { "<leader>ap", function() require("opencode").select() end, desc = "OpenCode Actions", mode = { "n", "v" } },
      {
        "<leader>aq",
        function()
          require("opencode").ask()
        end,
        desc = "OpenCode (Prompt)",
        mode = { "n", "v" }
      },
      {
        "<leader>ad",
        function()
          require("opencode").prompt("explain")
        end,
        desc = "OpenCode Explain",
        mode = { "n", "v" }
      },
      {
        "<leader>af",
        function()
          require("opencode").prompt("fix")
        end,
        desc = "OpenCode Fix",
        mode = { "n", "v" }
      },
      {
        "<leader>al",
        function()
          require("opencode").prompt("diagnostics")
        end,
        desc = "OpenCode Diagnostics",
        mode = { "n", "v" }
      },
      {
        "<leader>at",
        function()
          require("opencode").toggle()
        end,
        desc = "OpenCode Toggle",
        mode = { "n", "t" }
      },
    },
  },
  {
    "MeanderingProgrammer/render-markdown.nvim",
    ft = { "markdown" }
  },
}
