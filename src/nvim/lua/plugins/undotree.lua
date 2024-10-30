return {
  {
    'mbbill/undotree',
    event = "VeryLazy",
    config = function ()
      vim.keymap.set('n', '<leader>h', vim.cmd.UndotreeToggle, { desc = "Undotree toggle." })
    end
  }
}
