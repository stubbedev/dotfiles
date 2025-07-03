return {
  {
    'mbbill/undotree',
    event = "VeryLazy",
    config = function ()
      vim.keymap.set('n', '<leader>z', vim.cmd.UndotreeToggle, { desc = "Undotree toggle." })
      vim.keymap.set('v', '<leader>z', vim.cmd.UndotreeToggle, { desc = "Undotree toggle." })
    end
  }
}
