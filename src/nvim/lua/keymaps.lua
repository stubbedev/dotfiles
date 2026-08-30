-- Keymaps. nvim 0.12 already provides grn/gra/grr/gri (LSP), gc (comment),
-- ]d/[d (diagnostics) and ]q/[q (quickfix), so this file only adds what the
-- editor doesn't.

local map = vim.keymap.set

-- Windows -------------------------------------------------------------------
--
-- LazyVim bound all of these and they are pure muscle memory, so they are
-- carried over verbatim.

map("n", "<C-h>", "<C-w>h", { desc = "Go to left window", remap = true })
map("n", "<C-j>", "<C-w>j", { desc = "Go to lower window", remap = true })
map("n", "<C-k>", "<C-w>k", { desc = "Go to upper window", remap = true })
map("n", "<C-l>", "<C-w>l", { desc = "Go to right window", remap = true })

map("n", "<C-Up>", "<cmd>resize +2<cr>", { desc = "Increase window height" })
map("n", "<C-Down>", "<cmd>resize -2<cr>", { desc = "Decrease window height" })
map("n", "<C-Left>", "<cmd>vertical resize -2<cr>", { desc = "Decrease window width" })
map("n", "<C-Right>", "<cmd>vertical resize +2<cr>", { desc = "Increase window width" })

map("n", "<leader>-", "<C-w>s", { desc = "Split window below", remap = true })
map("n", "<leader>|", "<C-w>v", { desc = "Split window right", remap = true })
map("n", "<leader>wd", "<C-w>c", { desc = "Delete window", remap = true })
map("n", "<leader>ww", "<C-w>p", { desc = "Other window", remap = true })

-- Moving and editing ----------------------------------------------------------

map("n", "<A-j>", "<cmd>execute 'move .+' . v:count1<cr>==", { desc = "Move line down" })
map("n", "<A-k>", "<cmd>execute 'move .-' . (v:count1 + 1)<cr>==", { desc = "Move line up" })
map("i", "<A-j>", "<esc><cmd>m .+1<cr>==gi", { desc = "Move line down" })
map("i", "<A-k>", "<esc><cmd>m .-2<cr>==gi", { desc = "Move line up" })
map("x", "<A-j>", ":<C-u>execute \"'<,'>move '>+\" . v:count1<cr>gv=gv", { desc = "Move selection down" })
map("x", "<A-k>", ":<C-u>execute \"'<,'>move '<-\" . (v:count1 + 1)<cr>gv=gv", { desc = "Move selection up" })

-- Keep the selection after indenting, and keep the cursor put on join.
map("x", "<", "<gv")
map("x", ">", ">gv")
map("n", "J", "mzJ`z", { desc = "Join line, keep cursor" })

-- Centre the view on search jumps and half-page scrolls.
map("n", "n", "nzzzv", { desc = "Next search result" })
map("n", "N", "Nzzzv", { desc = "Prev search result" })
map("n", "<C-d>", "<C-d>zz")
map("n", "<C-u>", "<C-u>zz")

map({ "i", "x", "n", "s" }, "<C-s>", "<cmd>w<cr><esc>", { desc = "Save file" })

-- Buffers -------------------------------------------------------------------

map("n", "<S-h>", "<cmd>bprevious<cr>", { desc = "Prev buffer" })
map("n", "<S-l>", "<cmd>bnext<cr>", { desc = "Next buffer" })
map("n", "[b", "<cmd>bprevious<cr>", { desc = "Prev buffer" })
map("n", "]b", "<cmd>bnext<cr>", { desc = "Next buffer" })

local function delete_buffers(keep_current)
  local current = vim.api.nvim_get_current_buf()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].buflisted and not (keep_current and buf == current) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end
end

map("n", "<leader>bA", function()
  delete_buffers(false)
end, { desc = "Delete all buffers" })
map("n", "<leader>ba", function()
  delete_buffers(true)
end, { desc = "Delete other buffers" })
map("n", "<leader>bd", "<cmd>bdelete<cr>", { desc = "Delete buffer" })

-- Files and search ----------------------------------------------------------

-- fzf-lua is deferred (lua/plugins.lua), so it is required inside the
-- callbacks rather than at file scope -- requiring it here would load it
-- during startup and undo the deferral.
local function fzf(fn)
  return function()
    require("fzf-lua")[fn]()
  end
end

map("n", "<leader><space>", fzf("files"), { desc = "Find files" })
map("n", "<leader>ff", fzf("files"), { desc = "Find files" })
map("n", "<leader>fg", fzf("git_files"), { desc = "Find git files" })
map("n", "<leader>fr", fzf("oldfiles"), { desc = "Recent files" })
map("n", "<leader>fb", fzf("buffers"), { desc = "Buffers" })
map("n", "<leader>fh", fzf("helptags"), { desc = "Help" })
map("n", "<leader>fk", fzf("keymaps"), { desc = "Keymaps" })
map("n", "<leader>sk", fzf("keymaps"), { desc = "Keymaps" })
map("n", "<leader>sd", fzf("diagnostics_document"), { desc = "Document diagnostics" })
map("n", "<leader>sh", fzf("helptags"), { desc = "Help" })
map("n", "<leader>/", fzf("live_grep"), { desc = "Grep" })
map("n", "<leader>sg", fzf("live_grep"), { desc = "Grep" })
map("n", "<leader>sw", fzf("grep_cword"), { desc = "Grep word under cursor" })
map("x", "<leader>sw", fzf("grep_visual"), { desc = "Grep selection" })
map("n", "<leader>sr", fzf("resume"), { desc = "Resume last picker" })
map("n", "<leader>ss", fzf("lsp_document_symbols"), { desc = "Document symbols" })
map("n", "<leader>sS", fzf("lsp_live_workspace_symbols"), { desc = "Workspace symbols" })

map("n", "-", "<cmd>Oil<cr>", { desc = "Oil (parent dir)" })
map("n", "<leader>E", "<cmd>Oil<cr>", { desc = "Oil file explorer" })

-- Diagnostics and quickfix --------------------------------------------------

-- This is what trouble.nvim was for; the quickfix list does the same job.
map("n", "<leader>xx", function()
  vim.diagnostic.setqflist({ open = true })
end, { desc = "Diagnostics to quickfix" })
map("n", "<leader>xd", function()
  vim.diagnostic.setqflist({ open = true, bufnr = 0 })
end, { desc = "Buffer diagnostics to quickfix" })
map("n", "<leader>xl", "<cmd>lopen<cr>", { desc = "Location list" })
map("n", "<leader>cd", vim.diagnostic.open_float, { desc = "Line diagnostics" })

-- Search and replace across the project ---------------------------------------
--
-- <leader>sR opens grug-far on ripgrep (text), <leader>sA on ast-grep
-- (structural). Use the ast-grep one for renames: `$A.foo($B)` ->
-- `$A.bar($B)` rewrites call sites without touching a string or comment that
-- happens to read the same.
map("n", "<leader>sR", function()
  require("grug-far").open()
end, { desc = "Search/replace in project (ripgrep)" })
map("n", "<leader>sA", function()
  require("grug-far").open({ engine = "astgrep" })
end, { desc = "Structural search/replace (ast-grep)" })
map("x", "<leader>sR", function()
  require("grug-far").with_visual_selection()
end, { desc = "Search/replace selection" })
map("n", "<leader>sf", function()
  require("grug-far").open({ prefills = { paths = vim.fn.expand("%") } })
end, { desc = "Search/replace in this file" })

-- Sessions --------------------------------------------------------------------

map("n", "<leader>qs", "<cmd>SessionRestore<cr>", { desc = "Restore session for cwd" })
map("n", "<leader>qS", "<cmd>SessionSave<cr>", { desc = "Save session" })
map("n", "<leader>qd", "<cmd>SessionDelete<cr>", { desc = "Delete session" })

-- LSP, LazyVim spelling. nvim 0.12 already binds grn/gra/grr/gri; these are
-- the <leader>c aliases that are muscle memory from LazyVim.
map("n", "<leader>cr", vim.lsp.buf.rename, { desc = "Rename symbol" })
map({ "n", "x" }, "<leader>ca", vim.lsp.buf.code_action, { desc = "Code action" })

-- Formatting ----------------------------------------------------------------

map({ "n", "x" }, "<leader>cf", function()
  require("conform").format({ async = true, lsp_format = "fallback" })
end, { desc = "Format buffer" })

-- Misc ----------------------------------------------------------------------

map("n", "<leader>ur", "<cmd>nohlsearch<cr>", { desc = "Clear search highlight" })
map("n", "<esc>", "<cmd>nohlsearch<cr>", { desc = "Clear search highlight" })
map("n", "<leader>qq", "<cmd>qa<cr>", { desc = "Quit all" })
map("n", "gx", function()
  vim.ui.open(vim.fn.expand("<cfile>"))
end, { desc = "Open with system app" })
map({ "n", "v" }, "<leader>z", "<cmd>UndotreeToggle<cr>", { desc = "Undotree" })
map("n", "<leader>ll", function()
  vim.pack.update()
end, { desc = "Update plugins" })

-- Leave terminal mode. Not <esc><esc>: zsh-vim-mode owns <esc>, and the
-- mapping would swallow the second one and delay the first by timeoutlen.
-- Alacritty already sends <C-space> as CSI u, so this works in both GUIs.
map("t", "<C-space>", "<C-\\><C-n>", { desc = "Enter normal mode" })
