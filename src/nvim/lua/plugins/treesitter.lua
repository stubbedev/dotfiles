return {
  "nvim-treesitter/nvim-treesitter",
  build = ":TSUpdate",
  dependencies = {
    { "nvim-treesitter/nvim-treesitter-textobjects" },
    { "nvim-treesitter/nvim-treesitter-context" },
    { "nvim-treesitter/nvim-treesitter-refactor" },
    {
      "folke/todo-comments.nvim",
      opts = {},
      keys = {
        { "<leader>xt", "<cmd>TodoTelescope<cr>", desc = "Todos in project." }
      }
    }
  },
  opts = {
      ensure_installed = {
        "lua",
        "c",
        "go",
        "rust",
        "javascript",
        "html",
        "css",
        "php",
        "python",
        "vim"
      },
      highlight = { enable = true },
      indent = { enable = true },
  }
}
