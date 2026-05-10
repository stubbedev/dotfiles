return {
  {
    "folke/noice.nvim",
    event = "VeryLazy",
    opts = {
      lsp = {
        -- Neovim 0.12 changed the LSP hover/signature API to async with a
        -- different `result.contents` shape; noice's overrides crash with
        -- "attempt to index local 'content' (a userdata value)" against
        -- the new contracts. Fall back to the built-in handlers — they
        -- render hover/signature fine on their own.
        hover = { enabled = false },
        signature = { enabled = false },
        message = { enabled = false },
      },
      -- Route low-signal write/yank/jump messages to the mini view so they
      -- don't pop the cmdline.
      routes = {
        {
          filter = {
            event = "msg_show",
            any = {
              { find = "%d+L, %d+B" },
              { find = "; after #%d+" },
              { find = "; before #%d+" },
            },
          },
          view = "mini",
        },
      },
      presets = {
        bottom_search = true,
        command_palette = true,
        long_message_to_split = true,
      },
    },
  },
}
