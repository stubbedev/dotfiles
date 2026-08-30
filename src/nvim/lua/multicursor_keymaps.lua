-- Multicursor keymaps. Separate from lua/keymaps.lua because multicursor is
-- deferred: this module is required from the post-UI hook in lua/plugins.lua,
-- after the plugin has actually been sourced.

local map = vim.keymap.set
local mc = require("multicursor-nvim")

-- Add or skip a cursor above/below the main one.
--
-- On Alt, not the bare arrow keys. Under LazyVim this plugin was declared with
-- no `keys`/`event`/`cmd` and `defaults.lazy = true`, so it had no load trigger
-- and never actually loaded -- these mappings never existed and the arrows just
-- moved the cursor. Binding them globally broke plain arrow movement
-- everywhere, oil included.
map({ "n", "x" }, "<M-Up>", function()
  mc.lineAddCursor(-1)
end, { desc = "Multicursor: add cursor above" })
map({ "n", "x" }, "<M-Down>", function()
  mc.lineAddCursor(1)
end, { desc = "Multicursor: add cursor below" })
map({ "n", "x" }, "<leader><Up>", function()
  mc.lineSkipCursor(-1)
end, { desc = "Multicursor: skip cursor above" })
map({ "n", "x" }, "<leader><Down>", function()
  mc.lineSkipCursor(1)
end, { desc = "Multicursor: skip cursor below" })

-- Add/skip a cursor by matching word/selection, under <leader>m so the
-- <leader>n / <leader>s namespaces stay free.
map({ "n", "x" }, "<leader>mn", function()
  mc.matchAddCursor(1)
end, { desc = "Multicursor: match add cursor forward" })
map({ "n", "x" }, "<leader>ms", function()
  mc.matchSkipCursor(1)
end, { desc = "Multicursor: match skip cursor forward" })
map({ "n", "x" }, "<leader>mN", function()
  mc.matchAddCursor(-1)
end, { desc = "Multicursor: match add cursor backward" })
map({ "n", "x" }, "<leader>mS", function()
  mc.matchSkipCursor(-1)
end, { desc = "Multicursor: match skip cursor backward" })

-- A cursor per line in a motion or selection.
map({ "n", "x" }, "ga", mc.addCursorOperator, { desc = "Multicursor: add cursor per line in motion" })

-- Disable and enable cursors.
map({ "n", "x" }, "<c-q>", mc.toggleCursor, { desc = "Multicursor: toggle cursors enabled" })

-- These only apply while multiple cursors exist, so they can overlap with
-- normal mappings.
mc.addKeymapLayer(function(layer)
  layer({ "n", "x" }, "<M-Left>", mc.prevCursor, { desc = "Multicursor: previous cursor" })
  layer({ "n", "x" }, "<M-Right>", mc.nextCursor, { desc = "Multicursor: next cursor" })
  layer({ "n", "x" }, "<leader>mx", mc.deleteCursor, { desc = "Multicursor: delete cursor" })
  layer("n", "<esc>", function()
    if not mc.cursorsEnabled() then
      mc.enableCursors()
    else
      mc.clearCursors()
    end
  end, { desc = "Multicursor: enable or clear cursors" })
end)

local hl = vim.api.nvim_set_hl
hl(0, "MultiCursorCursor", { reverse = true })
hl(0, "MultiCursorVisual", { link = "Visual" })
hl(0, "MultiCursorSign", { link = "SignColumn" })
hl(0, "MultiCursorMatchPreview", { link = "Search" })
hl(0, "MultiCursorDisabledCursor", { reverse = true })
hl(0, "MultiCursorDisabledVisual", { link = "Visual" })
hl(0, "MultiCursorDisabledSign", { link = "SignColumn" })
