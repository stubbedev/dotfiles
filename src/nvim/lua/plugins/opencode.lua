return {
  {
    "sudo-tee/opencode.nvim",
    config = function()
      require("opencode").setup({
        ui = {
          input = {
            text = {
              wrap = true,
            },
          },
        },
        context = {
          enabled = true, -- Enable automatic context capturing
          cursor_data = {
            enabled = true, -- Include cursor position and line content in the context
            context_lines = 5, -- Number of lines before and after cursor to include in context
          },
          diagnostics = {
            info = true,   -- Include diagnostics info in the context (default to false
            warn = true,    -- Include diagnostics warnings in the context
            error = true,   -- Include diagnostics errors in the context
            only_closest = false, -- If true, only diagnostics for cursor/selection
          },
          current_file = {
            enabled = true, -- Include current file path and content in the context
            show_full_path = true,
          },
          files = {
            enabled = true,
            show_full_path = true,
          },
          selection = {
            enabled = true, -- Include selected text in the context
          },
          buffer = {
            enabled = false, -- Disable entire buffer context by default, only used in quick chat
          },
          git_diff = {
            enabled = true,
          },
        },
      })
    end,
    dependencies = {
      "nvim-lua/plenary.nvim",
      {
        "MeanderingProgrammer/render-markdown.nvim",
        opts = {
          anti_conceal = { enabled = false },
          file_types = { 'markdown', 'opencode_output' },
        },
        ft = { 'markdown', 'Avante', 'copilot-chat', 'opencode_output' },
      },
      'saghen/blink.cmp',
      'folke/snacks.nvim',
    },
  }
}
