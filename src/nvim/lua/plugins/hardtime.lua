return {
  {
    "m4xshen/hardtime.nvim",
    dependencies = { "MunifTanjim/nui.nvim", "nvim-lua/plenary.nvim" },
    opts = {
      max_count = 3,
      disabled_filetypes = { "qf", "netrw", "NvimTree", "lazy", "mason", "oil" },
    },
    keys = {
      { '<leader>ht', '<cmd>Hardtime toggle<cr>', desc = "Toggle HardTime" },
    }
  },
}
