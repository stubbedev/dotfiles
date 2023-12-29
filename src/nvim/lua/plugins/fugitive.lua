return {
  'tpope/vim-fugitive',
  lazy = false,
  url = "https://tpope.io/vim/fugitive.git",
  config = function ()
    require('fugitive.vim').setup()
  end,
  keys = {
    { "<leader>ga", "<cmd>Git add %<cmd>p<cr><cr>", desc = "Git add current file" },
    { "<leader>gs", "<cmd>Gstatus<cr>", desc = "Git status" },
    { "<leader>gc", "<cmd>Gcommit -v -q<CR>", desc = "Git commit." },
    { "<leader>gt", "<cmd>Gcommit -v -q %<cmd>p<CR>", desc = "Git commit with message." },
    { "<leader>gd", "<cmd>Gdiff<CR>", desc = "Git diff." },
    { "<leader>ge", "<cmd>Gedit<CR>", desc = "Git edit." },
    { "<leader>gr", "<cmd>Gread<CR>", desc = "Git read." },
    { "<leader>gw", "<cmd>Gwrite<CR><CR>", desc = "Git write." },
    { "<leader>gl", "<cmd>silent! Glog<CR><cmd>bot copen<CR>", desc = "Git list" },
    { "<leader>gp", "<cmd>Ggrep<Space>", desc = "Git grep" },
    { "<leader>gm", "<cmd>Gmove<Space>", desc = "Git move" },
    { "<leader>gb", "<cmd>Git branch<Space>", desc = "Git branch" },
    { "<leader>go", "<cmd>Git checkout<Space>", desc = "Git checkout" },
    { "<leader>gps", "<cmd>Dispatch! git push<CR>", desc = "Git push" },
    { "<leader>gpl", "<cmd>Dispatch! git pull<CR>", desc = "Git pull" },
  }
}
