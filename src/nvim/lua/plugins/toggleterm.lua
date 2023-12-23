return {
  {
    'akinsho/toggleterm.nvim',
    version = "*",
    config = function()
      require("toggleterm").setup({})
      function _G.set_terminal_keymaps()
        local opts = { buffer = 0 }
        vim.keymap.set('t', '<esc>', [[<C-\><C-n>]], opts)
        vim.keymap.set('t', '<esc><esc>', [[<C-\><C-n><Cmd>:ToggleTerm<CR>]], opts)
        vim.keymap.set('t', 'jk', [[<C-\><C-n>]], opts)
        vim.keymap.set('t', '<C-h>', [[<Cmd>wincmd h<CR>]], opts)
        vim.keymap.set('t', '<C-j>', [[<Cmd>wincmd j<CR>]], opts)
        vim.keymap.set('t', '<C-k>', [[<Cmd>wincmd k<CR>]], opts)
        vim.keymap.set('t', '<C-l>', [[<Cmd>wincmd l<CR>]], opts)
        vim.keymap.set('t', '<C-w>', [[<C-\><C-n><C-w>]], opts)
      end

      vim.keymap.set('n', '<leader>tt', ':ToggleTerm direction=float<cr>', { desc = "Terminal floating." })
      vim.keymap.set('n', '<leader>tv', ':ToggleTerm direction=vertical size=60<cr>', { desc = "Terminal vertical." })
      vim.keymap.set('n', '<leader>ts', ':ToggleTerm direction=horizontal size=20<cr>', { desc = "Terminal horizontal." })
      vim.cmd('autocmd! TermOpen term://* lua set_terminal_keymaps()')
    end
  }
}
