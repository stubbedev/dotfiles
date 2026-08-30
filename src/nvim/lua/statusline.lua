
local M = {}

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
  local status = vim.diagnostic.status()
  return status == "" and "" or (" " .. status .. " ")
end

local function macros()
  local ok, recorder = pcall(require, "recorder")
  if not ok then
    local reg = vim.fn.reg_recording()
    return reg == "" and "" or ("%#StRecord# REC @" .. reg .. " ")
  end
  local status = recorder.recordingStatus()
  if status ~= "" then
    return "%#StRecord# " .. status .. " "
  end

  local slots = recorder.displaySlots()
  if slots == "" then
    slots = "\u{f00cd} [ ]"
  end
  return "%#StFill# " .. slots .. " "
end

local function progress()
  local ok, status = pcall(vim.ui.progress_status)
  if not ok or not status or status == "" then
    return ""
  end
  return "%#StFill# " .. status:gsub("%%", "%%%%"):sub(1, 40) .. " "
end

local function branch()
  local head = vim.b.gitsigns_head
  if not head or head == "" then
    return ""
  end
  return "%#StBranch# \u{e0a0} " .. head .. " "
end

local function location()
  if vim.bo.buftype == "terminal" then
    return "terminal"
  end
  local ft = vim.bo.filetype
  if ft == "oil" then
    local ok, oil = pcall(require, "oil")
    local dir = ok and oil.get_current_dir()
    return dir and vim.fn.fnamemodify(dir, ":~") or "oil"
  end
  if vim.bo.buftype ~= "" then
    return ft ~= "" and ft or "[scratch]"
  end
  return "%f%m%r"
end

function M.render()
  local mode = modes[vim.api.nvim_get_mode().mode] or { "NORMAL", c.blue }
  hl("StMode", c.base, mode[2], true)

  return table.concat({
    "%#StMode# " .. mode[1] .. " ",
    branch(),
    "%#StFill# ",
    diagnostics(),
    progress(),
    "%=", -- right-align everything after this
    "%#StFile# " .. location() .. " ",
    "%#StFill# " .. (vim.bo.filetype ~= "" and vim.bo.filetype or "none") .. " ",
    macros(),
    "%#StMode# %l:%c  %P ",
  })
end


local function listed_buffers()
  return vim.tbl_filter(function(b)
    return vim.api.nvim_buf_is_loaded(b) and vim.bo[b].buflisted
  end, vim.api.nvim_list_bufs())
end

vim.api.nvim_create_autocmd({ "BufAdd", "BufDelete", "BufEnter", "BufWipeout" }, {
  group = vim.api.nvim_create_augroup("statusline_tabline", { clear = true }),
  callback = function()
    vim.schedule(function()
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
