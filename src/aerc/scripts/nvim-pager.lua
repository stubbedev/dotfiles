-- Aerc viewer post-processor.
--
-- Rewrites every [text](url) in the buffer to just `text`, and attaches
-- the URL as an OSC 8 hyperlink via an `url=` extmark on the surviving
-- text. Bare http(s):// URLs get the same extmark treatment but stay
-- visible.
--
-- Why rewrite instead of conceal: vim's wrap point is computed from raw
-- buffer bytes, not from concealed/extmarked display width. So both the
-- built-in `conceal` and render-markdown.nvim's extmark conceal still
-- wrap the line as if the URL were visible, leaving phantom blank rows
-- after the visible text. Removing the URL from the buffer is the only
-- thing that actually fixes the wrap.
--
-- OSC 8 click still works because the `url` extmark attribute makes
-- nvim's TUI emit a hyperlink for the underlying text, which Alacritty
-- recognises (hyperlinks = true on the default URL hint).

local ns = vim.api.nvim_create_namespace("aerc_links")
local bufnr = 0

-- LazyVim turns spellcheck on for markdown by default, which underlines
-- every non-English word (names, ticket IDs, hashes, Danish prose, ...).
-- Useless noise in a read-only viewer.
vim.wo.spell = false

-- Read-only mail viewer: no line numbers, no statusline, and bounce out
-- of any insert-flavoured mode. Visual / visual-block stay usable for
-- selecting text to yank.
vim.wo.number = false
vim.wo.relativenumber = false
vim.wo.signcolumn = "no"

-- Hide lualine + tabline. The user's init.lua re-runs lualine.setup()
-- via a scheduled callback on BufAdd (to refresh the bufferline tabline),
-- which resets laststatus and undoes a one-shot hide() call. Setup()
-- itself fires no autocmd, so we wrap it: every future setup() call
-- re-applies our hide as its last act.
local function hide_chrome()
  vim.o.laststatus = 0
  vim.o.showtabline = 0
  pcall(function() require("lualine").hide({ unhide = false }) end)
end

local ok, lualine = pcall(require, "lualine")
if ok then
  local orig_setup = lualine.setup
  lualine.setup = function(...)
    local ret = orig_setup(...)
    hide_chrome()
    return ret
  end
end
hide_chrome()
-- Belt and braces: catch any restore that races past the wrapper
-- (other plugins poking laststatus directly, etc.).
vim.defer_fn(hide_chrome, 50)
vim.defer_fn(hide_chrome, 500)

vim.api.nvim_create_autocmd("InsertEnter", {
  group = vim.api.nvim_create_augroup("AercBlockInsert", { clear = true }),
  callback = function() vim.cmd("stopinsert") end,
})

for _, key in ipairs({ "i", "I", "a", "A", "o", "O", "s", "S", "c", "C", "R", "gi", "gI", "gR" }) do
  vim.keymap.set("n", key, "<Nop>", { buffer = bufnr, silent = true })
end
for _, key in ipairs({ "i", "I", "a", "A", "s", "S", "c", "C", "r", "R" }) do
  vim.keymap.set("x", key, "<Nop>", { buffer = bufnr, silent = true })
end

-- Esc / q in normal mode: clear search highlight first, otherwise tell
-- aerc to close the viewer. Visual / visual-block don't need a mapping
-- -- their default Esc behaviour (exit to normal mode) is what we want,
-- and the next press will then either clear hlsearch or close the mail.
local function esc_or_close()
  if vim.v.hlsearch == 1 then
    vim.cmd("nohlsearch")
  else
    vim.fn.jobstart({ "aerc", ":close" }, { detach = true })
  end
end
vim.keymap.set("n", "<Esc>", esc_or_close, { buffer = bufnr, silent = true })
vim.keymap.set("n", "q", esc_or_close, { buffer = bufnr, silent = true })

-- Markdown inline link, optionally with a "title" attribute. URL stops
-- at the first whitespace or ')'; anything between URL and closing paren
-- (e.g. a quoted title) is dropped along with the brackets.
local md_pat = "%[([^%]]+)%]%(([^%s)]+)[^)]*%)"

-- Bare http(s):// URLs not already inside markdown syntax. The character
-- class trims punctuation that's typically prose, not URL.
local bare_pat = "()(https?://[^%s)%]>\"']+)()"

-- Link highlight group that render-markdown.nvim uses for inline links.
-- We mirror the colour here because we strip the markdown syntax from
-- the buffer above, so render-markdown has nothing left to style. No
-- virt_text icon: it adds visual columns that render-markdown's table
-- border math doesn't account for, so links inside table cells push the
-- border out of alignment.
local link_hl = "RenderMarkdownLink"

local function set_link_extmark(row, col, end_col, url)
  pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, row, col, {
    end_col = end_col,
    url = url,
    hl_group = link_hl,
  })
end

vim.bo[bufnr].readonly = false
vim.bo[bufnr].modifiable = true

local last = vim.api.nvim_buf_line_count(bufnr)
for lnum = 1, last do
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1] or ""

  local parts = {}
  local link_ranges = {}
  local cursor = 1
  local new_byte = 0
  local rewritten = false

  while true do
    local s, e, text, url = line:find(md_pat, cursor)
    if not s then break end
    rewritten = true
    local prefix = line:sub(cursor, s - 1)
    table.insert(parts, prefix)
    new_byte = new_byte + #prefix
    local link_start = new_byte
    table.insert(parts, text)
    new_byte = new_byte + #text
    table.insert(link_ranges, { s = link_start, e = new_byte, url = url })
    cursor = e + 1
  end

  if rewritten then
    table.insert(parts, line:sub(cursor))
    line = table.concat(parts)
    vim.api.nvim_buf_set_lines(bufnr, lnum - 1, lnum, false, { line })
    for _, r in ipairs(link_ranges) do
      set_link_extmark(lnum - 1, r.s, r.e, r.url)
    end
  end

  for s, url, e in line:gmatch(bare_pat) do
    set_link_extmark(lnum - 1, s - 1, e - 1, url)
  end
end

vim.bo[bufnr].modified = false
vim.bo[bufnr].modifiable = false
vim.bo[bufnr].readonly = true

-- Show the URL of the link under the cursor as a virtual line below.
-- The link itself is just plain text in the buffer (we stripped the
-- markdown syntax above), so without this you'd have no way to see
-- where a link points before clicking it.
local hover_ns = vim.api.nvim_create_namespace("aerc_link_hover")
vim.api.nvim_create_autocmd("CursorMoved", {
  buffer = bufnr,
  callback = function()
    vim.api.nvim_buf_clear_namespace(bufnr, hover_ns, 0, -1)
    local pos = vim.api.nvim_win_get_cursor(0)
    local row, col = pos[1] - 1, pos[2]
    local marks = vim.api.nvim_buf_get_extmarks(
      bufnr, ns,
      { row, 0 },
      { row, -1 },
      { details = true }
    )
    for _, m in ipairs(marks) do
      local mcol, details = m[3], m[4]
      local end_col = details.end_col or mcol
      if details.url and mcol <= col and col < end_col then
        vim.api.nvim_buf_set_extmark(bufnr, hover_ns, row, 0, {
          virt_lines = { { { "↳ " .. details.url, "Comment" } } },
        })
        return
      end
    end
  end,
})
