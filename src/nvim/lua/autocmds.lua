-- Autocommands.

local function augroup(name)
  return vim.api.nvim_create_augroup("stubbe_" .. name, { clear = true })
end

-- Treesitter ---------------------------------------------------------------
--
-- Parsers and queries come from nix (modules/nvim.nix drops them on the
-- packpath), so there is no nvim-treesitter Lua to configure -- starting the
-- built-in highlighter per filetype is the whole integration.
vim.api.nvim_create_autocmd("FileType", {
  group = augroup("treesitter"),
  callback = function(args)
    if vim.b[args.buf].bigfile then
      return
    end
    pcall(vim.treesitter.start, args.buf)
  end,
})

-- Big files ----------------------------------------------------------------
--
-- This is what snacks.bigfile did. Without it, opening a generated file (the
-- 131MB resultCache.php in a Laravel cache dir, a bundled .js) locks the UI
-- while treesitter and the LSP try to parse it.
vim.api.nvim_create_autocmd("BufReadPre", {
  group = augroup("bigfile"),
  callback = function(args)
    local ok, stat = pcall(vim.uv.fs_stat, vim.api.nvim_buf_get_name(args.buf))
    if not ok or not stat or stat.size < 1.5 * 1024 * 1024 then
      return
    end
    vim.b[args.buf].bigfile = true
    vim.opt_local.foldmethod = "manual"
    vim.opt_local.spell = false
    vim.opt_local.swapfile = false
    vim.opt_local.undofile = false
    vim.opt_local.list = false
    -- syntax off is deferred: the filetype that triggers it isn't set yet.
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(args.buf) then
        vim.bo[args.buf].syntax = ""
      end
    end)
  end,
})

-- Diagnostics --------------------------------------------------------------

-- .env files are matched by filename, not filetype: they're usually detected
-- as "sh", and a shell linter has strong opinions about KEY=value files.
vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
  group = augroup("env"),
  pattern = { ".env", ".env.*", "*.env" },
  callback = function(args)
    vim.diagnostic.enable(false, { bufnr = args.buf })
  end,
})

-- Quality of life ----------------------------------------------------------

vim.api.nvim_create_autocmd("TextYankPost", {
  group = augroup("yank"),
  callback = function()
    vim.hl.on_yank()
  end,
})

-- Reopen a file where you left it.
vim.api.nvim_create_autocmd("BufReadPost", {
  group = augroup("last_loc"),
  callback = function(args)
    if vim.b[args.buf].last_loc then
      return
    end
    vim.b[args.buf].last_loc = true
    local mark = vim.api.nvim_buf_get_mark(args.buf, '"')
    local lines = vim.api.nvim_buf_line_count(args.buf)
    if mark[1] > 0 and mark[1] <= lines then
      pcall(vim.api.nvim_win_set_cursor, 0, mark)
    end
  end,
})

-- Writing to a path whose directory doesn't exist yet should just work.
vim.api.nvim_create_autocmd("BufWritePre", {
  group = augroup("mkdir"),
  callback = function(args)
    if args.match:match("^%w%w+://") then
      return
    end
    vim.fn.mkdir(vim.fn.fnamemodify(vim.uv.fs_realpath(args.match) or args.match, ":p:h"), "p")
  end,
})

-- Close throwaway windows with plain `q`.
vim.api.nvim_create_autocmd("FileType", {
  group = augroup("close_with_q"),
  pattern = { "help", "qf", "man", "checkhealth", "lspinfo", "query", "startuptime" },
  callback = function(args)
    vim.bo[args.buf].buflisted = false
    vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = args.buf, silent = true })
  end,
})

-- Keep splits proportional when the terminal is resized.
vim.api.nvim_create_autocmd("VimResized", {
  group = augroup("resize"),
  command = "tabdo wincmd =",
})
