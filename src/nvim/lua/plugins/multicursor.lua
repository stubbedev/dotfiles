return {
  {
    "jake-stewart/multicursor.nvim",
    branch = "1.0",
    config = function()
      local mc = require("multicursor-nvim")
      mc.setup()

      local set = vim.keymap.set

      -- Add or skip cursor above/below the main cursor.
      set({ "n", "x" }, "<up>", function()
        mc.lineAddCursor(-1)
      end, { desc = "Multicursor: add cursor above" })
      set({ "n", "x" }, "<down>", function()
        mc.lineAddCursor(1)
      end, { desc = "Multicursor: add cursor below" })
      set({ "n", "x" }, "<leader><up>", function()
        mc.lineSkipCursor(-1)
      end, { desc = "Multicursor: skip cursor above" })
      set({ "n", "x" }, "<leader><down>", function()
        mc.lineSkipCursor(1)
      end, { desc = "Multicursor: skip cursor below" })

      -- Add or skip adding a new cursor by matching word/selection.
      set({ "n", "x" }, "<leader>n", function()
        mc.matchAddCursor(1)
      end, { desc = "Multicursor: match add cursor forward" })
      set({ "n", "x" }, "<leader>s", function()
        mc.matchSkipCursor(1)
      end, { desc = "Multicursor: match skip cursor forward" })
      set({ "n", "x" }, "<leader>N", function()
        mc.matchAddCursor(-1)
      end, { desc = "Multicursor: match add cursor backward" })
      set({ "n", "x" }, "<leader>S", function()
        mc.matchSkipCursor(-1)
      end, { desc = "Multicursor: match skip cursor backward" })

      -- Add and remove cursors with control + left click.
      set("n", "<c-leftmouse>", mc.handleMouse, { desc = "Multicursor: toggle cursor" })
      set("n", "<c-leftdrag>", mc.handleMouseDrag, { desc = "Multicursor: drag cursors" })
      set("n", "<c-leftrelease>", mc.handleMouseRelease, { desc = "Multicursor: release drag" })

      -- Disable and enable cursors.
      set({ "n", "x" }, "<c-q>", mc.toggleCursor, { desc = "Multicursor: toggle cursors enabled" })

      -- Mappings defined in a keymap layer only apply when there are
      -- multiple cursors. This lets you have overlapping mappings.
      mc.addKeymapLayer(function(layerSet)
        -- Select a different cursor as the main one.
        layerSet({ "n", "x" }, "<left>", mc.prevCursor, { desc = "Multicursor: previous cursor" })
        layerSet({ "n", "x" }, "<right>", mc.nextCursor, { desc = "Multicursor: next cursor" })

        -- Delete the main cursor.
        layerSet({ "n", "x" }, "<leader>x", mc.deleteCursor, { desc = "Multicursor: delete cursor" })

        -- Enable and clear cursors using escape.
        layerSet("n", "<esc>", function()
          if not mc.cursorsEnabled() then
            mc.enableCursors()
          else
            mc.clearCursors()
          end
        end, { desc = "Multicursor: enable or clear cursors" })
      end)

      -- Customize how cursors look.
      local hl = vim.api.nvim_set_hl
      hl(0, "MultiCursorCursor", { reverse = true })
      hl(0, "MultiCursorVisual", { link = "Visual" })
      hl(0, "MultiCursorSign", { link = "SignColumn" })
      hl(0, "MultiCursorMatchPreview", { link = "Search" })
      hl(0, "MultiCursorDisabledCursor", { reverse = true })
      hl(0, "MultiCursorDisabledVisual", { link = "Visual" })
      hl(0, "MultiCursorDisabledSign", { link = "SignColumn" })
    end,
  },
}
