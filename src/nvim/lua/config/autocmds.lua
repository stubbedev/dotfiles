-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
-- Add any additional autocmds here
-- wrap and check for spell in text filetypes

-- Disable diagnostics for .env files (matched by filename, not filetype,
-- since .env files are typically detected as "sh" filetype)
vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
  pattern = { ".env", ".env.*", "*.env" },
  callback = function(args)
    vim.diagnostic.enable(false, { bufnr = args.buf })
  end,
})
