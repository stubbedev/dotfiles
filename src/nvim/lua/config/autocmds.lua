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

vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    vim.lsp.inlay_hint.enable(false, { bufnr = args.buf })
  end,
})

-- PHP: format with the project's Pint on save. Global autoformat is off
-- (config/options.lua), so this fires only where the project ships
-- vendor/bin/pint — per-project by detection, no per-repo config, and it
-- resolves upward so it works inside git worktrees too.
vim.api.nvim_create_autocmd("BufWritePre", {
  group = vim.api.nvim_create_augroup("php_pint_on_save", { clear = true }),
  pattern = "*.php",
  callback = function(args)
    local dir = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(args.buf), ":h")
    if not vim.fs.find("vendor/bin/pint", { upward = true, path = dir })[1] then
      return
    end
    require("conform").format({ bufnr = args.buf, formatters = { "pint" }, lsp_format = "never" })
  end,
})
