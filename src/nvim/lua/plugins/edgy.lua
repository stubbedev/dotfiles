return {
  "folke/edgy.nvim",
  config = function()
    require("edgy").setup({
      animate = {
        enabled = false,
      },
    })
  end,
}
