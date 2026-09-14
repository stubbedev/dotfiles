local M = {}

function M.map(lhs, t)
  vim.keymap.set("n", lhs, function()
    local state = not t.get()
    t.set(state)
    vim.notify((state and "Enabled " or "Disabled ") .. t.name, vim.log.levels.INFO)
  end, { desc = "Toggle " .. t.name })
end

function M.option(name, opts)
  opts = opts or {}
  local on = opts.on
  if on == nil then
    on = true
  end
  local off = opts.off
  if off == nil then
    off = false
  end
  local scope = opts.scope or "o"
  return {
    name = opts.name or name,
    get = function()
      return vim[scope][name] == on
    end,
    set = function(state)
      vim[scope][name] = state and on or off
    end,
  }
end

M.diagnostics = {
  name = "Diagnostics",
  get = function()
    return vim.diagnostic.is_enabled()
  end,
  set = function(state)
    vim.diagnostic.enable(state)
  end,
}

M.inlay_hints = {
  name = "Inlay Hints",
  get = function()
    return vim.lsp.inlay_hint.is_enabled({ bufnr = 0 })
  end,
  set = function(state)
    vim.lsp.inlay_hint.enable(state, { bufnr = 0 })
  end,
}

M.treesitter = {
  name = "Treesitter Highlight",
  get = function()
    return vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()] ~= nil
  end,
  set = function(state)
    if state then
      pcall(vim.treesitter.start)
    else
      pcall(vim.treesitter.stop)
    end
  end,
}

M.gitsigns = {
  name = "Git Signs",
  get = function()
    local ok, config = pcall(require, "gitsigns.config")
    return ok and config.config.signcolumn
  end,
  set = function(state)
    require("gitsigns").toggle_signs(state)
  end,
}

return M
