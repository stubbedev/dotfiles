return {
  {
    "saghen/blink.cmp",
    opts_extend = {
      "sources.default",
      "sources.providers"
    },
    opts = {
      sources = {
        completion = { documentation = { auto_show = true } },
        default = { "lsp", "buffer", "snippets", "path" },
      },
    },
  }
}
