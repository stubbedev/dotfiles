return {
  {
    'akinsho/toggleterm.nvim',
    version = "*",
    config = function()
      require("toggleterm").setup({})
      function _G.set_terminal_keymaps()
        local opts = { buffer = 0, silent = true }
        vim.keymap.set('t', '<esc>', [[<C-\><C-n>]], opts)
        vim.keymap.set('t', '<esc><esc>', [[<C-\><C-n><Cmd>:ToggleTerm<CR>]], opts)
        vim.keymap.set({'t','n','x','v','i'}, '<C-_>', [[<C-\><C-n><Cmd>:ToggleTerm name=companion<CR>]], opts)
        vim.keymap.set('t', 'jk', [[<C-\><C-n>]], opts)
        vim.keymap.set('t', '<C-h>', [[<Cmd>wincmd h<CR>]], opts)
        vim.keymap.set('t', '<C-j>', [[<Cmd>wincmd j<CR>]], opts)
        vim.keymap.set('t', '<C-k>', [[<Cmd>wincmd k<CR>]], opts)
        vim.keymap.set('t', '<C-l>', [[<Cmd>wincmd l<CR>]], opts)
        vim.keymap.set('t', '<C-w>', [[<C-\><C-n><C-w>]], opts)
      end

      vim.keymap.set({'n','x'}, '<leader>tt', ':ToggleTerm direction=float name=float<cr>', { desc = "Terminal floating.", silent = true})
      vim.keymap.set({'n','x'}, '<leader>tv', ':ToggleTerm direction=vertical size=60 name=right<cr>', { desc = "Terminal vertical.", silent = true })
      vim.keymap.set({'n','x'}, '<leader>ts', ':ToggleTerm direction=horizontal size=20 name=bottom<cr>', { desc = "Terminal horizontal.", silent = true})
      vim.keymap.set({'n','x','v','i'}, '<C-_>', ':ToggleTerm direction=horizontal size=30 name=companion<cr>',
        { desc = "Terminal horizontal.", silent = true })
      vim.cmd('autocmd! TermOpen term://* lua set_terminal_keymaps()')
    end
  }
}

