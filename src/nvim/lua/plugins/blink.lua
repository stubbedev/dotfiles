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
      "fuzzy.sorts",
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
      fuzzy = {
        sorts = {
          -- Float AI completions to the top. Keyed on source_id rather than
          -- client_name: blink sets source_id for every provider, but
          -- client_name only for LSP-backed ones, and codeium is a plain
          -- module provider.
          function(a, b)
            if (a.source_id == nil or b.source_id == nil) or (a.source_id == b.source_id) then
              return
            end
            return a.source_id == 'codeium'
          end,
          'score',
          'sort_text'
        }
      },
      sources = {
        default = { "lsp", "buffer", "snippets", "path", "codeium" },
        providers = {
          codeium = {
            name = "codeium",
            module = "codeium.blink",
            score_offset = 100,
            async = true,
          },
        },
      },
    },
  }
}
