return {
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    init = function()
      vim.o.timeout = true
      vim.o.timeoutlen = 500
    end,
    opts = {}
  },
  {
    "chentoast/marks.nvim",
    opts = {
      default_mappings = false,
      cyclic = true,
      builtin_marks = { ".", "<", ">", "^", "'" },
      mappings = {
        set_next = '<leader>mn',
        annotate = '<leader>ma',
        next = '<leader>n',
        prev = '<leader>N',
        preview = '<leader>mp',
        delete_line = '<leader>md',
        delete_buf = '<leader>me',
        set_bookmark0 = '<leader>m0',
        set_bookmark1 = '<leader>m1',
        set_bookmark2 = '<leader>m2',
        set_bookmark3 = '<leader>m3',
        set_bookmark4 = '<leader>m4',
        set_bookmark5 = '<leader>m5',
        set_bookmark6 = '<leader>m6',
        set_bookmark7 = '<leader>m7',
        set_bookmark8 = '<leader>m8',
        set_bookmark9 = '<leader>m9',
        next_bookmark = '<leader>mb',
        prev_bookmark = '<leader>mB',
        delete_bookmark = '<leader>mD',
      }
    },
  }
}
