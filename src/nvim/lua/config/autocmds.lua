-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
-- Add any additional autocmds here
-- wrap and check for spell in text filetypes

vim.api.nvim_create_autocmd("FileType", {
  pattern = { "coffee" },
  callback = function()
    vim.opt_local.shiftwidth = 4
    vim.opt_local.softtabstop = 4
    vim.opt_local.expandtab = true
  end,
})

vim.api.nvim_create_autocmd({"FileWritePost", "BufWritePost"}, {
  pattern = { "*.coffee" },
  callback = function()
    local repo_name = vim.fn.system("basename `git rev-parse --show-toplevel 2>/dev/null` 2>/dev/null"):gsub("%s+", "")
    if repo_name == 'clerk.js' then
      vim.loop.spawn("bash", {
        args = {"-c", "source venv/bin/activate && ./build.sh --debug && cp clerk.js ../live.clerk.io/live.clerk.io"},
        detached = true,
      })
    end
  end,
})
