return {
  "nvim-treesitter/nvim-treesitter",
  build = ":TSUpdate",
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
