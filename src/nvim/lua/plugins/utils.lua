return {
  {
    "aserowy/tmux.nvim",
    opts = {}
  },
  {
    'windwp/nvim-autopairs',
    event = "InsertEnter",
    opts = {
      disable_filetype = { "TelescopePrompt", "vim" },
    }
  },
  {
    'echasnovski/mini.comment',
    version = '*',
    opts = {
      options = {
        ignore_blank_line = true,
        start_of_line = false,
        pad_comment_parts = true,
      },
    }
  }
}
