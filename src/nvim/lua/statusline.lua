-- Statusline and tabline, hand-rolled on the native 'statusline'/'tabline'
-- options. This replaces lualine.
--
-- Worth knowing why it's hand-rolled rather than "one more plugin": the old
-- lualine tabline rebuilt itself by calling lualine.setup() -- a full ~3ms
-- re-init -- on every BufAdd/BufDelete. A native expression is re-evaluated by
-- the redraw loop instead, so showing the buffer list costs nothing.

local M = {}

-- Catppuccin Mocha, matching lua/options.lua's terminal palette.
local c = {
  base = "#1e1e2e",
  mantle = "#181825",
  surface0 = "#313244",
  surface1 = "#45475a",
  text = "#cdd6f4",
  subtext = "#a6adc8",
  blue = "#89b4fa",
  mauve = "#cba6f7",
  green = "#a6e3a1",
  peach = "#fab387",
  red = "#f38ba8",
  yellow = "#f9e2af",
  teal = "#94e2d5",
}

local modes = {
  n = { "NORMAL", c.blue },
  i = { "INSERT", c.green },
  v = { "VISUAL", c.mauve },
  V = { "V-LINE", c.mauve },
  ["\22"] = { "V-BLOCK", c.mauve },
  s = { "SELECT", c.mauve },
  S = { "S-LINE", c.mauve },
  R = { "REPLACE", c.red },
  c = { "COMMAND", c.peach },
  t = { "TERMINAL", c.teal },
}

local function hl(name, fg, bg, bold)
  vim.api.nvim_set_hl(0, name, { fg = fg, bg = bg, bold = bold })
end

local function set_highlights()
  hl("StMode", c.base, c.blue, true)
  hl("StBranch", c.text, c.surface1)
  hl("StFile", c.text, c.surface0)
  hl("StFill", c.subtext, c.mantle)
  hl("StRecord", c.base, c.red, true)
  hl("StError", c.red, c.mantle)
  hl("StWarn", c.yellow, c.mantle)
  hl("StHint", c.teal, c.mantle)
  hl("StInfo", c.blue, c.mantle)
  -- Tabline
  hl("TabLineSel", c.base, c.blue, true)
  hl("TabLine", c.subtext, c.surface0)
  hl("TabLineFill", c.subtext, c.mantle)
end

set_highlights()
vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("statusline_hl", { clear = true }),
  callback = set_highlights,
})

local function diagnostics()
  local counts = vim.diagnostic.count(0)
  local parts = {}
  local severities = {
    { vim.diagnostic.severity.ERROR, "StError", "\u{f057} " },
    { vim.diagnostic.severity.WARN, "StWarn", "\u{f071} " },
    { vim.diagnostic.severity.INFO, "StInfo", "\u{f05a} " },
    { vim.diagnostic.severity.HINT, "StHint", "\u{f0eb} " },
  }
  for _, s in ipairs(severities) do
    local n = counts[s[1]] or 0
    if n > 0 then
      table.insert(parts, ("%%#%s#%s%d"):format(s[2], s[3], n))
    end
  end
  return table.concat(parts, " ")
end

-- nvim-recorder's macro slots. Falls back to nvim's own reg_recording() if the
-- plugin ever goes away, so the statusline never errors.
local function macros()
  local ok, recorder = pcall(require, "recorder")
  if not ok then
    local reg = vim.fn.reg_recording()
    return reg == "" and "" or ("%#StRecord# REC @" .. reg .. " ")
  end
  local status = recorder.recordingStatus()
  local slots = recorder.displaySlots()
  local out = {}
  if status ~= "" then
    table.insert(out, "%#StRecord# " .. status .. " ")
  end
  if slots ~= "" then
    table.insert(out, "%#StFill# " .. slots .. " ")
  end
  return table.concat(out)
end

local function branch()
  local head = vim.b.gitsigns_head
  if not head or head == "" then
    return ""
  end
  return "%#StBranch# \u{e0a0} " .. head .. " "
end

function M.render()
  local mode = modes[vim.api.nvim_get_mode().mode] or { "NORMAL", c.blue }
  hl("StMode", c.base, mode[2], true)

  return table.concat({
    "%#StMode# " .. mode[1] .. " ",
    branch(),
    "%#StFill# ",
    diagnostics(),
    "%=", -- right-align everything after this
    "%#StFile# %f%m%r ",
    "%#StFill# " .. (vim.bo.filetype ~= "" and vim.bo.filetype or "none") .. " ",
    macros(),
    "%#StMode# %l:%c  %P ",
  })
end

-- Tabline: the list of listed buffers, but only once there are at least two --
-- a single-buffer tabline is a wasted line.

local function listed_buffers()
  return vim.tbl_filter(function(b)
    return vim.api.nvim_buf_is_loaded(b) and vim.bo[b].buflisted
  end, vim.api.nvim_list_bufs())
end

-- 'showtabline' has to be set from an autocmd, not from inside M.tabline():
-- an option written during the redraw that is evaluating the tabline doesn't
-- take effect, so the bar silently never appears.
vim.api.nvim_create_autocmd({ "BufAdd", "BufDelete", "BufEnter", "BufWipeout" }, {
  group = vim.api.nvim_create_augroup("statusline_tabline", { clear = true }),
  callback = function()
    vim.schedule(function()
      -- Only assign when it changes: BufEnter fires constantly, and writing
      -- the option is what forces a redraw.
      local want = #listed_buffers() > 1 and 2 or 1
      if vim.o.showtabline ~= want then
        vim.o.showtabline = want
      end
    end)
  end,
})

function M.tabline()
  local bufs = listed_buffers()
  if #bufs < 2 then
    return ""
  end

  local current = vim.api.nvim_get_current_buf()
  local parts = {}
  for _, b in ipairs(bufs) do
    local name = vim.api.nvim_buf_get_name(b)
    name = name == "" and "[No Name]" or vim.fn.fnamemodify(name, ":t")
    local flag = vim.bo[b].modified and " ●" or ""
    table.insert(parts, ("%%#%s# %s%s "):format(b == current and "TabLineSel" or "TabLine", name, flag))
  end
  return table.concat(parts) .. "%#TabLineFill#"
end

vim.o.statusline = "%!v:lua.require'statusline'.render()"
vim.o.tabline = "%!v:lua.require'statusline'.tabline()"

return M
