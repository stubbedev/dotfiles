-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
-- Add any additional autocmds here
-- wrap and check for spell in text filetypes

vim.api.nvim_create_autocmd("FileType", {
  pattern = { "coffee" },
  callback = function()
    vim.opt_local.shiftwidth = 4
    vim.opt_local.softtabstop = 4
    vim.opt_local.expandtab = true
  end,
})

vim.api.nvim_create_autocmd({ "FileWritePost", "BufWritePost" }, {
  pattern = { "*.coffee" },
  callback = function()
    local repo_name = vim.fn.system("basename `git rev-parse --show-toplevel 2>/dev/null` 2>/dev/null"):gsub("%s+", "")
    if repo_name == "clerk.js" then
      vim.fn.jobstart(
        "bash -c 'source venv/bin/activate && ./build.sh --debug && \\cp -rf clerk.js ../live.clerk.io/live.clerk.io'",
        {
          on_exit = function(_, code)
            if code ~= 0 then
              vim.notify("Build process exited with code " .. code, vim.log.levels.WARN)
            end
          end,
        }
      )
    end
    vim.cmd(":CoffeeLint | cwindow")
    -- vim.fn.jobstart("coffeelint " .. vim.api.nvim_buf_get_name(0), {
    --   on_stdout = function(_, data)
    --     vim.notify(data, vim.log.levels.INFO)
    --     if data and #data > 0 then
    --       vim.fn.setqflist({}, " ", { title = "CoffeeLint", lines = data })
    --       vim.cmd("cwindow")
    --     end
    --   end,
    -- on_stderr = function(_, data)
    --   if data and #data > 0 then
    --     vim.notify("CoffeeLint error: " .. table.concat(data, "\n"), vim.log.levels.ERROR)
    --   end
    -- end,
    -- on_exit = function(_, code)
    --   if code ~= 0 then
    --     vim.notify("CoffeeLint exited with code " .. code, vim.log.levels.WARN)
    --   end
    -- end,
    -- })
  end,
})
