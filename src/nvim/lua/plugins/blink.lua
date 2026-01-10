return {
  {
    "saghen/blink.cmp",
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
          function(a, b)
            if (a.client_name == nil or b.client_name == nil) or (a.client_name == b.client_name) then
              return
            end
            return a.client_name == 'copilot'
          end,
          'score',
          'sort_text'
        }
      },
      sources = {
        default = { "lsp", "buffer", "snippets", "path" },
        per_filetype = {
          opencode_input = { "path" }, -- Only enable path completions for OpenCode input
        },
      },
    },
  }
}
