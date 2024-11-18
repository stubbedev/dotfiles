return {
  {
    "kchmck/vim-coffee-script",
    event = "VeryLazy",
    config = function() end,
  },
  {
    "phil294/coffeesense",
    config = function()
      require("lspconfig").coffeesense.setup({
        cmd = { "coffeesense-language-server", "--stdio" }, -- Command to start the language server
        filetypes = { "coffee" }, -- Filetypes to attach the server to
        root_dir = require("lspconfig").util.root_pattern(".git", "package.json"), -- Root directory for the project
        settings = {}, -- Additional settings, if any
      })
    end,
  },
}
