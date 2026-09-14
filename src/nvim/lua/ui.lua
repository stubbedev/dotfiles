local M = {}

function M.zoom()
  if vim.t.zoomed then
    vim.cmd.tabclose()
  else
    vim.cmd("tab split")
    vim.t.zoomed = true
  end
end

local zen_saved = nil

function M.zen()
  if zen_saved then
    for option, value in pairs(zen_saved) do
      vim.o[option] = value
    end
    zen_saved = nil
    if vim.t.zoomed then
      vim.cmd.tabclose()
    end
    return
  end
  zen_saved = {
    number = vim.o.number,
    relativenumber = vim.o.relativenumber,
    signcolumn = vim.o.signcolumn,
    laststatus = vim.o.laststatus,
    showtabline = vim.o.showtabline,
  }
  M.zoom()
  vim.o.number = false
  vim.o.relativenumber = false
  vim.o.signcolumn = "no"
  vim.o.laststatus = 0
  vim.o.showtabline = 0
end

local scratch_dir = vim.fs.joinpath(vim.fn.stdpath("data"), "scratch")

function M.scratch_dir()
  return scratch_dir
end

local function scratch_path()
  local ft = vim.bo.filetype
  if ft == "" or ft == "oil" or vim.bo.buftype ~= "" then
    ft = "markdown"
  end
  local ext = ft == "markdown" and "md" or ft
  local slug = (vim.uv.cwd() or ""):gsub("^" .. vim.pesc(vim.env.HOME or ""), ""):gsub("[^%w]+", "-"):gsub("^-", "")
  return vim.fs.joinpath(scratch_dir, (slug == "" and "root" or slug) .. "." .. ext)
end

local scratch_win = nil

function M.scratch()
  if scratch_win and vim.api.nvim_win_is_valid(scratch_win) then
    vim.api.nvim_win_close(scratch_win, false)
    scratch_win = nil
    return
  end

  vim.fn.mkdir(scratch_dir, "p")
  M.open_float(vim.fn.bufadd(scratch_path()), " scratch ")
  scratch_win = vim.api.nvim_get_current_win()
  vim.bo.bufhidden = "hide"
  vim.api.nvim_create_autocmd("BufWinLeave", {
    buffer = vim.api.nvim_get_current_buf(),
    once = true,
    callback = function(args)
      if vim.bo[args.buf].modified then
        vim.api.nvim_buf_call(args.buf, function()
          vim.cmd("silent write")
        end)
      end
      scratch_win = nil
    end,
  })
  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = true, desc = "Close scratch" })
end

function M.open_float(buf, title)
  local width = math.floor(vim.o.columns * 0.85)
  local height = math.floor(vim.o.lines * 0.85)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) * 0.4),
    col = math.floor((vim.o.columns - width) / 2),
    border = "rounded",
    title = title,
    title_pos = "center",
  })
  vim.wo[win].winfixbuf = false
  return win
end

return M
