return {
  -- blink.cmp v2 was split into two repos: the cmp engine (saghen/blink.cmp)
  -- and a shared Rust/Lua library (saghen/blink.lib) that lazy.nvim has to
  -- install alongside, otherwise `require('blink.lib')` from blink.cmp's
  -- init fails with "module 'blink.lib' not found". Newer LazyVim revisions
  -- declare this dependency upstream; declaring it here keeps the spec
  -- working across LazyVim updates.
  { "saghen/blink.lib" },
  {
    "saghen/blink.cmp",
    dependencies = { "saghen/blink.lib" },
    opts_extend = {
      "sources.default",
      "completion.documentation",
      "signature",
    },
    opts = {
      completion = {
        documentation = {
          auto_show = true,
          auto_show_delay_ms = 500
        },
      },
      signature = {
        enabled = true,
        window = {
          show_documentation = false
        }
      },
      -- No custom `fuzzy.sorts`: a Lua comparator drops blink out of its Rust
      -- sorter and back into a Lua sort on every keystroke (~40% of blink's
      -- per-key cost). Everything in this menu is LSP/buffer/snippet/path
      -- now, and blink's Rust scorer ranks those on its own.
    },
  }
}
