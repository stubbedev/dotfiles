return {
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    opts = {
      ensure_installed = { "caddy", "css", "scss", "nix" },
    },
  },
}
