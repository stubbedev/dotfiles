-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
-- Add any additional autocmds here
-- wrap and check for spell in text filetypes

-- Disable diagnostics for .env files
vim.api.nvim_create_autocmd("FileType", {
  pattern = "env",
  callback = function()
    vim.diagnostic.disable(0)
  end,
})

