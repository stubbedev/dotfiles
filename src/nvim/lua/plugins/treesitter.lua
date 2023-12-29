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
    },
    {
      'kevinhwang91/nvim-ufo',
      dependencies = { 'kevinhwang91/promise-async' },
      config = function()
        require('ufo').setup()
        vim.keymap.set('n', 'zR', require('ufo').openAllFolds, { desc = "Open all folds." })
        vim.keymap.set('n', 'zM', require('ufo').closeAllFolds, { desc = "Close all folds." })
        vim.o.foldcolumn = '1'
        vim.o.foldlevel = 99
        vim.o.foldlevelstart = 99
        vim.o.foldenable = true
      end
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
      "vim",
      "markdown",
      "org"
    },
    highlight = {
      enable = true
    },
    indent = { enable = true },
  }
}

