-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
-- Add any additional autocmds here
-- wrap and check for spell in text filetypes

-- Disable diagnostics for .env files
vim.api.nvim_create_autocmd("FileType", {
  pattern = "env",
  callback = function()
    vim.diagnostic.disable(0)
  end,
})

-- Function to parse PHPStorm configurations for on-save actions
local function parse_phpstorm_config()
  local idea_dir = vim.fn.getcwd() .. '/.idea'
  if vim.fn.isdirectory(idea_dir) == 0 then return {} end

  local actions = {}

  -- Check php.xml for external formatter
  local php_xml = idea_dir .. '/php.xml'
  if vim.fn.filereadable(php_xml) == 1 then
    local lines = vim.fn.readfile(php_xml)
    local content = table.concat(lines, '\n')
    if content:find('<option name="externalFormatter" value="LARAVEL_PINT"') then
      table.insert(actions, {program = 'vendor/bin/pint', args = '%', wd = vim.fn.getcwd()})
    end
    -- If PhpStan component exists, assume it runs on save (though in practice it may not)
    if content:find('<component name="PhpStan">') then
      table.insert(actions, {program = 'vendor/bin/phpstan analyse --quiet --no-progress --error-format=raw', args = '%', wd = vim.fn.getcwd()})
    end
  end

  -- Check watcherTasks.xml for file watchers with immediateSync
  local wt_xml = idea_dir .. '/watcherTasks.xml'
  if vim.fn.filereadable(wt_xml) == 1 then
    local lines = vim.fn.readfile(wt_xml)
    local content = table.concat(lines, '\n')
    for task in content:gmatch('<TaskOptions[^>]*>(.-)</TaskOptions>') do
      local enabled = task:find('<option name="isEnabled" value="true"')
      if enabled then
        local immediate = task:find('<option name="immediateSync" value="true"')
        if immediate then
          local program = task:match('<option name="program" value="([^"]*)"')
          local args = task:match('<option name="arguments" value="([^"]*)"') or ''
          local wd = task:match('<option name="workingDir" value="([^"]*)"') or vim.fn.getcwd()
          if program then
            table.insert(actions, {program = program, args = args:gsub('$FileRelativePath$', '%'), wd = wd})
          end
        end
      end
    end
  end

  return actions
end

-- Run PHPStorm configured actions on save for PHP files
vim.api.nvim_create_autocmd("BufWritePre", {
  pattern = "*.php",
  callback = function()
    local actions = parse_phpstorm_config()
    for _, a in ipairs(actions) do
      local cmd = string.format('cd %s && %s %s', vim.fn.shellescape(a.wd), a.program, a.args:gsub('%%', vim.fn.expand('%')))
      vim.fn.system(cmd)
    end
  end,
})

