return {
  { "echasnovski/mini.indentscope", enabled = false },
  { "goolord/alpha-nvim",           enabled = false },
  { "folke/flash.nvim",             enabled = false },
  {
    "folke/snacks.nvim",
    opts_extend = { "explorer", "scroll", "indent", "picker", "image" },
    opts = {
      explorer = { enabled = false },
      scroll = { enabled = false },
      indent = { enabled = false },
      picker = { enabled = false },
      image = { enabled = false },
    }
  },
}
