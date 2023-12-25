return {
  {
    "catppuccin/nvim",
    name = "catppuccin",
    priority = 1000 ,
    lazy = false,
    opts = {
      colorscheme = "catppuccin",
      flavour = "macchiato",
      integrations = {
        gitsigns = true,
        cmp = true,
        nvimtree = true,
        treesitter = true,
        notify = true,
        barbar = true,
        mason = true,
        which_key = true,
        telescope = true,
      },
      transparent_background = true,
      background = {
        light = "mocha",
        dark = "latte"
      }
    }
  }
}
