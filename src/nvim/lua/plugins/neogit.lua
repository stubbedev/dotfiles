return {
  {
    "NeogitOrg/neogit",
    dependencies = {
      "nvim-lua/plenary.nvim", -- required
      "sindrets/diffview.nvim", -- optional - Diff integration

      -- Only one of these is needed, not both.
      "nvim-telescope/telescope.nvim", -- optional
    },
    config = true,
    keys = {
      { "<C-g>", '<cmd>lua require("neogit").open({ kind = "auto" })<cr>', desc = "Neogit" },
    },
  },
}
