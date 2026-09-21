vim.loader.enable()

require("options")
require("plugins")
require("statusline")
require("keymaps")
require("autocmds")

-- One tick after first draw: nothing here is needed before it. blink's module
-- is already on the runtimepath for lsp.lua's capabilities; vim.lsp.enable()
-- attaches to already-open buffers when it runs.
vim.schedule(function()
  require("lsp")
end)
