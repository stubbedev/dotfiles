-- Annotate markdown links with `url` extmarks so nvim's TUI emits OSC 8
-- hyperlinks. Alacritty's hint config already includes OSC 8 hyperlinks
-- (hyperlinks = true on the default URL hint), and unlike the regex-based
-- match those span wrapped lines — so clicks land on the right URL even
-- when the visible text breaks across two screen rows.

local ns = vim.api.nvim_create_namespace("aerc_links")
local bufnr = 0

-- Markdown inline links: [text](url). Patterns intentionally exclude
-- whitespace and ')' from the URL so we don't swallow trailing prose.
local md_pat = "()%[([^%]]+)%]%(([^%s)]+)%)()"

-- Bare http(s):// URLs not already wrapped in markdown syntax. The
-- character class trims punctuation that's typically prose, not URL.
local bare_pat = "()(https?://[^%s)%]>\"']+)()"

local last = vim.api.nvim_buf_line_count(bufnr)
for lnum = 1, last do
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1] or ""

  for s, _, url, e in line:gmatch(md_pat) do
    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, lnum - 1, s - 1, {
      end_col = e - 1,
      url = url,
    })
  end

  for s, url, e in line:gmatch(bare_pat) do
    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, lnum - 1, s - 1, {
      end_col = e - 1,
      url = url,
    })
  end
end
