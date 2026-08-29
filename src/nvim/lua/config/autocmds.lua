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
-- vendor/bin/pint -- per-project by detection, no per-repo config, and it
-- resolves upward so it works inside git worktrees too.
--
-- Async, on BufWritePost rather than BufWritePre: pint is a PHP process
-- running PHP-CS-Fixer and takes ~1.4s on a 2800-line file, so formatting
-- inline made every :w block for that long. conform applies the result only
-- if the buffer is untouched since the format started, so typing during
-- those 1.4s cancels the rewrite rather than clobbering the edit.
-- conform.nvim's own format_after_save can't be used here: LazyVim's conform
-- spec deletes opts.format_after_save and warns if it's set.
vim.api.nvim_create_autocmd("BufWritePost", {
  group = vim.api.nvim_create_augroup("php_pint_on_save", { clear = true }),
  pattern = "*.php",
  callback = function(args)
    local buf = args.buf
    local dir = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":h")
    if not vim.fs.find("vendor/bin/pint", { upward = true, path = dir })[1] then
      return
    end
    require("conform").format({
      bufnr = buf,
      formatters = { "pint" },
      lsp_format = "never",
      async = true,
      timeout_ms = 10000,
    }, function(err)
      -- Nothing to write back if pint failed or made no change.
      if err or not vim.api.nvim_buf_is_valid(buf) or not vim.bo[buf].modified then
        return
      end
      vim.api.nvim_buf_call(buf, function()
        vim.cmd("noautocmd silent write")
      end)
    end)
  end,
})
