return {
  {
    "saghen/blink.cmp",
    opts_extend = {
      "sources.default",
      "sources.providers"
    },
    opts = {
      sources = {
        default = { "lsp", "buffer", "snippets", "path", "blade-nav" },
        providers = {
          ["blade-nav"] = {
            module = "blade-nav.blink",
            opts = {
              close_tag_on_complete = true
            }
          }
        }
      },
    },
  }
}
