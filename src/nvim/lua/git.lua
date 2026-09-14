local M = {}

function M.root()
  local dir = vim.fs.root(0, ".git")
  return dir or vim.uv.cwd()
end

function M.lazygit(cwd)
  if vim.fn.executable("lazygit") == 0 then
    vim.notify("lazygit is not installed", vim.log.levels.ERROR)
    return
  end

  local buf = vim.api.nvim_create_buf(false, true)
  local win = require("ui").open_float(buf, " lazygit ")
  vim.bo[buf].bufhidden = "wipe"
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"

  vim.fn.jobstart({ "lazygit" }, {
    cwd = cwd or M.root(),
    term = true,
    on_exit = function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
      vim.cmd.checktime()
      pcall(function()
        require("gitsigns").refresh()
      end)
    end,
  })
  vim.cmd.startinsert()
end

local function git(root, args)
  local res = vim.system(vim.list_extend({ "git", "-C", root }, args), { text = true }):wait()
  return res.code == 0 and vim.trim(res.stdout) or nil
end

function M.url()
  local root = M.root()
  local remote = git(root, { "remote", "get-url", "origin" })
  if not remote then
    vim.notify("no origin remote", vim.log.levels.ERROR)
    return nil
  end

  remote = remote
    :gsub("^git@([^:]+):", "https://%1/")
    :gsub("^ssh://git@", "https://")
    :gsub("^ssh://", "https://")
    :gsub("%.git$", "")
    :gsub("/$", "")

  local branch = git(root, { "rev-parse", "--abbrev-ref", "HEAD" }) or "HEAD"
  if branch == "HEAD" then
    branch = git(root, { "rev-parse", "HEAD" }) or "HEAD"
  end

  local file = vim.api.nvim_buf_get_name(0)
  if file == "" or vim.bo.buftype ~= "" then
    return remote
  end
  file = vim.fs.relpath(root, file)
  if not file then
    return remote
  end
  local line = vim.api.nvim_win_get_cursor(0)[1]

  local project, repo = remote:match("/scm/([^/]+)/([^/]+)$")
  if project then
    local base = remote:gsub("/scm/[^/]+/[^/]+$", "")
    return ("%s/projects/%s/repos/%s/browse/%s?at=%s#%d"):format(base, project:upper(), repo, file, branch, line)
  end

  return ("%s/blob/%s/%s#L%d"):format(remote, branch, file, line)
end

function M.browse(copy)
  local url = M.url()
  if not url then
    return
  end
  if copy then
    vim.fn.setreg("+", url)
    vim.notify("Yanked " .. url)
  else
    vim.ui.open(url)
  end
end

return M
