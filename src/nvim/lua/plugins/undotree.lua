return {
  {
    'mbbill/undotree',
    event = "VeryLazy",
    config = function ()
      vim.keymap.set('n', '<leader>.', vim.cmd.UndotreeToggle, { desc = "Undotree toggle." })
    end
  }
}
