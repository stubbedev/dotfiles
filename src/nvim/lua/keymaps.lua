local map = vim.keymap.set
local toggle = require("toggle")

map({ "n", "x" }, "j", "v:count == 0 ? 'gj' : 'j'", { desc = "Down", expr = true, silent = true })
map({ "n", "x" }, "k", "v:count == 0 ? 'gk' : 'k'", { desc = "Up", expr = true, silent = true })
map({ "n", "x" }, "<Down>", "v:count == 0 ? 'gj' : 'j'", { desc = "Down", expr = true, silent = true })
map({ "n", "x" }, "<Up>", "v:count == 0 ? 'gk' : 'k'", { desc = "Up", expr = true, silent = true })

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
map("n", "<leader>wm", function()
  require("ui").zoom()
end, { desc = "Zoom window" })
map("n", "<leader>uZ", function()
  require("ui").zoom()
end, { desc = "Zoom window" })
map("n", "<leader>uz", function()
  require("ui").zen()
end, { desc = "Zen mode" })

map("n", "<A-j>", "<cmd>execute 'move .+' . v:count1<cr>==", { desc = "Move line down" })
map("n", "<A-k>", "<cmd>execute 'move .-' . (v:count1 + 1)<cr>==", { desc = "Move line up" })
map("i", "<A-j>", "<esc><cmd>m .+1<cr>==gi", { desc = "Move line down" })
map("i", "<A-k>", "<esc><cmd>m .-2<cr>==gi", { desc = "Move line up" })
map("x", "<A-j>", ":<C-u>execute \"'<,'>move '>+\" . v:count1<cr>gv=gv", { desc = "Move selection down" })
map("x", "<A-k>", ":<C-u>execute \"'<,'>move '<-\" . (v:count1 + 1)<cr>gv=gv", { desc = "Move selection up" })

map("x", "<", "<gv")
map("x", ">", ">gv")
map("n", "J", "mzJ`z", { desc = "Join line, keep cursor" })

map("n", "n", "'Nn'[v:searchforward].'zzzv'", { expr = true, desc = "Next search result" })
map("x", "n", "'Nn'[v:searchforward]", { expr = true, desc = "Next search result" })
map("o", "n", "'Nn'[v:searchforward]", { expr = true, desc = "Next search result" })
map("n", "N", "'nN'[v:searchforward].'zzzv'", { expr = true, desc = "Prev search result" })
map("x", "N", "'nN'[v:searchforward]", { expr = true, desc = "Prev search result" })
map("o", "N", "'nN'[v:searchforward]", { expr = true, desc = "Prev search result" })
map("n", "<C-d>", "<C-d>zz")
map("n", "<C-u>", "<C-u>zz")

map("i", ",", ",<c-g>u")
map("i", ".", ".<c-g>u")
map("i", ";", ";<c-g>u")

map({ "i", "x", "n", "s" }, "<C-s>", "<cmd>w<cr><esc>", { desc = "Save file" })

map("n", "gco", "o<esc>Vcx<esc><cmd>normal gcc<cr>fxa<bs>", { desc = "Add comment below" })
map("n", "gcO", "O<esc>Vcx<esc><cmd>normal gcc<cr>fxa<bs>", { desc = "Add comment above" })
map("n", "<leader>K", "<cmd>norm! K<cr>", { desc = "Keywordprg" })

map("n", "<S-h>", "<cmd>bprevious<cr>", { desc = "Prev buffer" })
map("n", "<S-l>", "<cmd>bnext<cr>", { desc = "Next buffer" })
map("n", "[b", "<cmd>bprevious<cr>", { desc = "Prev buffer" })
map("n", "]b", "<cmd>bnext<cr>", { desc = "Next buffer" })
map("n", "<leader>bb", "<cmd>e #<cr>", { desc = "Switch to other buffer" })
map("n", "<leader>`", "<cmd>e #<cr>", { desc = "Switch to other buffer" })

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
map("n", "<leader>bo", function()
  delete_buffers(true)
end, { desc = "Delete other buffers" })
map("n", "<leader>bd", "<cmd>bdelete<cr>", { desc = "Delete buffer" })
map("n", "<leader>bD", "<cmd>bdelete<cr><cmd>close<cr>", { desc = "Delete buffer and window" })

local function fzf(fn, opts)
  return function()
    require("fzf-lua")[fn](opts)
  end
end

map("n", "<leader><space>", fzf("files"), { desc = "Find files" })
map("n", "<leader>,", fzf("buffers"), { desc = "Buffers" })
map("n", "<leader>:", fzf("command_history"), { desc = "Command history" })
map("n", "<leader>ff", fzf("files"), { desc = "Find files" })
map("n", "<leader>fF", fzf("files", { cwd = vim.uv.cwd() }), { desc = "Find files (cwd)" })
map("n", "<leader>fg", fzf("git_files"), { desc = "Find git files" })
map("n", "<leader>fc", fzf("files", { cwd = vim.fn.stdpath("config") }), { desc = "Find config file" })
map("n", "<leader>fr", fzf("frecency", { cwd_only = true }), { desc = "Recent files (frecency)" })
map("n", "<leader>fR", fzf("oldfiles"), { desc = "Recent files" })
map("n", "<leader>fb", fzf("buffers"), { desc = "Buffers" })
map("n", "<leader>fB", fzf("buffers", { show_unlisted = true }), { desc = "Buffers (all)" })
map("n", "<leader>fh", fzf("helptags"), { desc = "Help" })
map("n", "<leader>fk", fzf("keymaps"), { desc = "Keymaps" })
map("n", "<leader>fn", "<cmd>enew<cr>", { desc = "New file" })

map("n", "<leader>/", fzf("live_grep"), { desc = "Grep" })
map("n", "<leader>sg", fzf("live_grep"), { desc = "Grep" })
map("n", "<leader>sG", fzf("live_grep", { cwd = vim.uv.cwd() }), { desc = "Grep (cwd)" })
map("n", "<leader>sb", fzf("blines"), { desc = "Buffer lines" })
map("n", "<leader>sB", fzf("lines"), { desc = "Grep open buffers" })
map("n", "<leader>sw", fzf("grep_cword"), { desc = "Grep word under cursor" })
map("x", "<leader>sw", fzf("grep_visual"), { desc = "Grep selection" })
map("n", "<leader>sW", fzf("grep_cword", { cwd = vim.uv.cwd() }), { desc = "Grep word under cursor (cwd)" })
map("n", '<leader>s"', fzf("registers"), { desc = "Registers" })
map("n", "<leader>s/", fzf("search_history"), { desc = "Search history" })
map("n", "<leader>sa", fzf("autocmds"), { desc = "Autocmds" })
map("n", "<leader>sc", fzf("command_history"), { desc = "Command history" })
map("n", "<leader>sC", fzf("commands"), { desc = "Commands" })
map("n", "<leader>sd", fzf("diagnostics_workspace"), { desc = "Diagnostics" })
map("n", "<leader>sD", fzf("diagnostics_document"), { desc = "Buffer diagnostics" })
map("n", "<leader>sh", fzf("helptags"), { desc = "Help" })
map("n", "<leader>sH", fzf("highlights"), { desc = "Highlights" })
map("n", "<leader>sj", fzf("jumps"), { desc = "Jumps" })
map("n", "<leader>sk", fzf("keymaps"), { desc = "Keymaps" })
map("n", "<leader>sl", fzf("loclist"), { desc = "Location list" })
map("n", "<leader>sm", fzf("marks"), { desc = "Marks" })
map("n", "<leader>sM", fzf("manpages"), { desc = "Man pages" })
map("n", "<leader>sq", fzf("quickfix"), { desc = "Quickfix list" })
map("n", "<leader>sR", fzf("resume"), { desc = "Resume last picker" })
map("n", "<leader>ss", fzf("lsp_document_symbols"), { desc = "Document symbols" })
map("n", "<leader>sS", fzf("lsp_live_workspace_symbols"), { desc = "Workspace symbols" })
map("n", "<leader>su", function()
  vim.cmd.packadd("nvim.undotree")
  vim.cmd.Undotree()
end, { desc = "Undo tree" })
map("n", "<leader>sn", "<cmd>messages<cr>", { desc = "Message history" })
map("n", "<leader>uC", fzf("colorschemes"), { desc = "Colorschemes" })

map("n", "-", "<cmd>Oil<cr>", { desc = "Oil (parent dir)" })
map("n", "<leader>E", "<cmd>Oil<cr>", { desc = "Oil file explorer" })

map("n", "<leader>cd", vim.diagnostic.open_float, { desc = "Line diagnostics" })

local function diag_jump(count, severity)
  return function()
    vim.diagnostic.jump({
      count = count * vim.v.count1,
      severity = severity and vim.diagnostic.severity[severity] or nil,
      float = true,
    })
  end
end
map("n", "]d", diag_jump(1), { desc = "Next diagnostic" })
map("n", "[d", diag_jump(-1), { desc = "Prev diagnostic" })
map("n", "]e", diag_jump(1, "ERROR"), { desc = "Next error" })
map("n", "[e", diag_jump(-1, "ERROR"), { desc = "Prev error" })
map("n", "]w", diag_jump(1, "WARN"), { desc = "Next warning" })
map("n", "[w", diag_jump(-1, "WARN"), { desc = "Prev warning" })

map("n", "<leader>xx", "<cmd>Trouble diagnostics toggle<cr>", { desc = "Diagnostics (Trouble)" })
map("n", "<leader>xX", "<cmd>Trouble diagnostics toggle filter.buf=0<cr>", { desc = "Buffer diagnostics (Trouble)" })
map("n", "<leader>xL", "<cmd>Trouble loclist toggle<cr>", { desc = "Location list (Trouble)" })
map("n", "<leader>xQ", "<cmd>Trouble qflist toggle<cr>", { desc = "Quickfix list (Trouble)" })
map("n", "<leader>xt", "<cmd>Trouble todo toggle<cr>", { desc = "Todo (Trouble)" })
map(
  "n",
  "<leader>xT",
  "<cmd>Trouble todo toggle filter = {tag = {TODO,FIX,FIXME}}<cr>",
  { desc = "Todo/Fix/Fixme (Trouble)" }
)
map("n", "<leader>st", "<cmd>TodoFzfLua<cr>", { desc = "Todo" })
map("n", "<leader>sT", "<cmd>TodoFzfLua keywords=TODO,FIX,FIXME<cr>", { desc = "Todo/Fix/Fixme" })

map("n", "<leader>xd", function()
  vim.diagnostic.setqflist({ open = true, bufnr = 0 })
end, { desc = "Buffer diagnostics to quickfix" })
map("n", "<leader>xl", function()
  local ok, err = pcall(vim.fn.getloclist(0, { winid = 0 }).winid ~= 0 and vim.cmd.lclose or vim.cmd.lopen)
  if not ok and err then
    vim.notify(err, vim.log.levels.ERROR)
  end
end, { desc = "Location list" })
map("n", "<leader>xq", function()
  local ok, err = pcall(vim.fn.getqflist({ winid = 0 }).winid ~= 0 and vim.cmd.cclose or vim.cmd.copen)
  if not ok and err then
    vim.notify(err, vim.log.levels.ERROR)
  end
end, { desc = "Quickfix list" })
map("n", "[q", vim.cmd.cprev, { desc = "Prev quickfix" })
map("n", "]q", vim.cmd.cnext, { desc = "Next quickfix" })

map("n", "<leader>gg", function()
  require("git").lazygit()
end, { desc = "Lazygit (root dir)" })
map("n", "<leader>gG", function()
  require("git").lazygit(vim.uv.cwd())
end, { desc = "Lazygit (cwd)" })
map({ "n", "x" }, "<leader>gB", function()
  require("git").browse()
end, { desc = "Git browse (open)" })
map({ "n", "x" }, "<leader>gY", function()
  require("git").browse(true)
end, { desc = "Git browse (copy)" })
map("n", "<leader>gb", fzf("git_blame"), { desc = "Git blame line" })
map("n", "<leader>gf", fzf("git_bcommits"), { desc = "Git current file history" })
map("n", "<leader>gl", fzf("git_commits"), { desc = "Git log" })
map("n", "<leader>gL", fzf("git_commits", { cwd = vim.uv.cwd() }), { desc = "Git log (cwd)" })
map("n", "<leader>gs", fzf("git_status"), { desc = "Git status" })
map("n", "<leader>gS", fzf("git_stash"), { desc = "Git stash" })
map("n", "<leader>gd", fzf("git_diff"), { desc = "Git diff (hunks)" })

map("n", "<leader><tab><tab>", "<cmd>tabnew<cr>", { desc = "New tab" })
map("n", "<leader><tab>d", "<cmd>tabclose<cr>", { desc = "Close tab" })
map("n", "<leader><tab>f", "<cmd>tabfirst<cr>", { desc = "First tab" })
map("n", "<leader><tab>l", "<cmd>tablast<cr>", { desc = "Last tab" })
map("n", "<leader><tab>o", "<cmd>tabonly<cr>", { desc = "Close other tabs" })
map("n", "<leader><tab>]", "<cmd>tabnext<cr>", { desc = "Next tab" })
map("n", "<leader><tab>[", "<cmd>tabprevious<cr>", { desc = "Prev tab" })

toggle.map("<leader>us", toggle.option("spell", { name = "Spelling" }))
toggle.map("<leader>uw", toggle.option("wrap", { name = "Wrap" }))
toggle.map("<leader>ul", toggle.option("number", { name = "Line Numbers" }))
toggle.map("<leader>uL", toggle.option("relativenumber", { name = "Relative Numbers" }))
toggle.map(
  "<leader>uc",
  toggle.option(
    "conceallevel",
    { off = 0, on = vim.o.conceallevel > 0 and vim.o.conceallevel or 2, name = "Conceal Level" }
  )
)
toggle.map(
  "<leader>uA",
  toggle.option("showtabline", { off = 0, on = vim.o.showtabline > 0 and vim.o.showtabline or 1, name = "Tabline" })
)
toggle.map("<leader>ub", toggle.option("background", { off = "light", on = "dark", name = "Dark Background" }))
toggle.map("<leader>ud", toggle.diagnostics)
toggle.map("<leader>uh", toggle.inlay_hints)
toggle.map("<leader>uT", toggle.treesitter)
toggle.map("<leader>uG", toggle.gitsigns)

map("n", "<leader>ui", vim.show_pos, { desc = "Inspect position" })
map("n", "<leader>uI", function()
  vim.treesitter.inspect_tree()
  vim.api.nvim_input("I")
end, { desc = "Inspect treesitter tree" })
map("n", "<leader>un", "<cmd>messages clear<cr>", { desc = "Dismiss messages" })

map("n", "<leader>?", function()
  require("which-key").show({ global = false })
end, { desc = "Buffer keymaps (which-key)" })
map("n", "<c-w><space>", function()
  require("which-key").show({ keys = "<c-w>", loop = true })
end, { desc = "Window hydra mode (which-key)" })

map({ "n", "x" }, "<leader>sr", function()
  local ext = vim.bo.buftype == "" and vim.fn.expand("%:e")
  require("grug-far").open({
    transient = true,
    prefills = { filesFilter = ext and ext ~= "" and "*." .. ext or nil },
  })
end, { desc = "Search and replace" })
map("n", "<leader>rr", function()
  require("grug-far").open()
end, { desc = "Search/replace in project (ripgrep)" })
map("n", "<leader>ra", function()
  require("grug-far").open({ engine = "astgrep" })
end, { desc = "Structural search/replace (ast-grep)" })
map("x", "<leader>rr", function()
  require("grug-far").with_visual_selection()
end, { desc = "Search/replace selection" })
map("n", "<leader>rf", function()
  require("grug-far").open({ prefills = { paths = vim.fn.expand("%") } })
end, { desc = "Search/replace in this file" })

map("n", "<leader>qs", "<cmd>SessionRestore<cr>", { desc = "Restore session for cwd" })
map("n", "<leader>ql", "<cmd>SessionRestore<cr>", { desc = "Restore last session" })
map("n", "<leader>qS", "<cmd>SessionSave<cr>", { desc = "Save session" })
map("n", "<leader>qd", "<cmd>SessionDelete<cr>", { desc = "Delete session" })
map("n", "<leader>qq", "<cmd>qa<cr>", { desc = "Quit all" })

map({ "n", "x" }, "<leader>cf", function()
  require("conform").format({ async = true, lsp_format = "fallback" })
end, { desc = "Format buffer" })

map("n", "<leader>.", function()
  require("ui").scratch()
end, { desc = "Toggle scratch buffer" })
map("n", "<leader>S", function()
  require("fzf-lua").files({ cwd = require("ui").scratch_dir() })
end, { desc = "Select scratch buffer" })

map("n", "<leader>ur", "<cmd>nohlsearch<bar>diffupdate<bar>normal! <C-L><cr>", { desc = "Redraw / clear hlsearch" })
map({ "i", "n", "s" }, "<esc>", function()
  vim.cmd("nohlsearch")
  if vim.snippet.active() then
    vim.snippet.stop()
  end
  return "<esc>"
end, { expr = true, desc = "Escape and clear hlsearch" })

map({ "n", "v" }, "<leader>z", function()
  vim.cmd.packadd("nvim.undotree")
  vim.cmd.Undotree()
end, { desc = "Undo tree" })
map("n", "<leader>ll", function()
  vim.pack.update()
end, { desc = "Update plugins" })

map("t", "<C-space>", "<C-\\><C-n>", { desc = "Enter normal mode" })
