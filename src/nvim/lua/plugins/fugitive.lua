return {
  'tpope/vim-fugitive',
  lazy = false,
  url = "https://tpope.io/vim/fugitive.git",
  keys = {
    { "<leader>ga", "<cmd>Git add %<cmd>p<cr><cr>", desc = "Git add current file" },
    { "<leader>gs", "<cmd>Gstatus<cr>", desc = "Git status" },
    { "<leader>gc", "<cmd>Gcommit -v -q<CR>", desc = "" },
    { "<leader>gt", "<cmd>Gcommit -v -q %<cmd>p<CR>", desc = "" },
    { "<leader>gd", "<cmd>Gdiff<CR>", desc = "" },
    { "<leader>ge", "<cmd>Gedit<CR>", desc = "" },
    { "<leader>gr", "<cmd>Gread<CR>", desc = "" },
    { "<leader>gw", "<cmd>Gwrite<CR><CR>", desc = "" },
    { "<leader>gl", "<cmd>silent! Glog<CR><cmd>bot copen<CR>", desc = "" },
    { "<leader>gp", "<cmd>Ggrep<Space>", desc = "" },
    { "<leader>gm", "<cmd>Gmove<Space>", desc = "" },
    { "<leader>gb", "<cmd>Git branch<Space>", desc = "" },
    { "<leader>go", "<cmd>Git checkout<Space>", desc = "" },
    { "<leader>gps", "<cmd>Dispatch! git push<CR>", desc = "" },
    { "<leader>gpl", "<cmd>Dispatch! git pull<CR>", desc = "" },
  }
}
