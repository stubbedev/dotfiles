return {
  "folke/edgy.nvim",
  event = "VeryLazy",
  config = function()
    require("edgy").setup({
      animate = {
        enabled = false,
      },
    })
  end,
}
