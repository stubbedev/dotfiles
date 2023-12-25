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
    keys = {
      { '<leader>mn', '<cmd>lua require("marks").set_next()<cr>', desc = "Marks: Set next"  },
      { '<leader>ma', '<cmd>lua require("marks").annotate()<cr>', desc = "Marks: Annotate"  },
      { '<leader>n', '<cmd>lua require("marks").next()<cr>', desc = "Marks: Next"  },
      { '<leader>N', '<cmd>lua require("marks").prev()<cr>', desc = "Marks: Previous"  },
      { '<leader>mp', '<cmd>lua require("marks").preview()<cr>', desc = "Marks: Preview"  },
      { '<leader>md', '<cmd>lua require("marks").delete_line()<cr>', desc = "Marks: Delete line"  },
      { '<leader>me', '<cmd>lua require("marks").delete_buf()<cr>', desc = "Marks: Delete buffer"  },
      { '<leader>m0', '<cmd>lua require("marks").set_bookmark0()<cr>', desc = "Marks: Set bookmark 0" },
      { '<leader>m1', '<cmd>lua require("marks").set_bookmark1()<cr>', desc = "Marks: Set bookmark 1" },
      { '<leader>m2', '<cmd>lua require("marks").set_bookmark2()<cr>', desc = "Marks: Set bookmark 2" },
      { '<leader>m3', '<cmd>lua require("marks").set_bookmark3()<cr>', desc = "Marks: Set bookmark 3" },
      { '<leader>m4', '<cmd>lua require("marks").set_bookmark4()<cr>', desc = "Marks: Set bookmark 4" },
      { '<leader>m5', '<cmd>lua require("marks").set_bookmark5()<cr>', desc = "Marks: Set bookmark 5" },
      { '<leader>m6', '<cmd>lua require("marks").set_bookmark6()<cr>', desc = "Marks: Set bookmark 6" },
      { '<leader>m7', '<cmd>lua require("marks").set_bookmark7()<cr>', desc = "Marks: Set bookmark 7" },
      { '<leader>m8', '<cmd>lua require("marks").set_bookmark8()<cr>', desc = "Marks: Set bookmark 8" },
      { '<leader>m9', '<cmd>lua require("marks").set_bookmark9()<cr>', desc = "Marks: Set bookmark 9" },
      { '<leader>mb', '<cmd>lua require("marks").next_bookmark()<cr>', desc = "Marks: Next bookmark" },
      { '<leader>mB', '<cmd>lua require("marks").prev_bookmark()<cr>', desc = "Marks: Previous bookmark" },
      { '<leader>mD', '<cmd>lua require("marks").delete_bookmark()<cr>', desc = "Marks: Delete bookmark" },
    },
    opts = {
      default_mappings = false,
      cyclic = true,
      builtin_marks = { ".", "<", ">", "^", "'" },
    },
  }
}
