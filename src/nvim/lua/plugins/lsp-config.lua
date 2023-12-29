local ensure_installed = {
  "bashls",
  "clangd",
  "neocmake",
  "cssls",
  "html",
  "gopls",
  "dockerls",
  "jsonls",
  "tsserver",
  "lua_ls",
  "marksman",
  "phpactor",
  "pyright",
  "rust_analyzer",
  "volar",
  "yamlls",
}

return {
  {
    "williamboman/mason.nvim",
    lazy = false,
    config = true,
  },

  -- Autocompletion
  {
    "hrsh7th/nvim-cmp",
    event = "InsertEnter",
    dependencies = {
      {
        "L3MON4D3/LuaSnip",
      },
      {
        "saadparwaiz1/cmp_luasnip",
      },
      {
        "hrsh7th/cmp-nvim-lsp",
      },
      {
        "nvim-lua/plenary.nvim",
      },
      {
        "Exafunction/codeium.nvim",
        event = "BufEnter",
        opts = {},
      },
    },
    config = function()
      local cmp = require("cmp")
      cmp.setup({
        snippet = {
          -- REQUIRED - you must specify a snippet engine
          expand = function(args)
            -- vim.fn["vsnip#anonymous"](args.body) -- For `vsnip` users.
            require("luasnip").lsp_expand(args.body) -- For `luasnip` users.
            -- require('snippy').expand_snippet(args.body) -- For `snippy` users.
            -- vim.fn["UltiSnips#Anon"](args.body) -- For `ultisnips` users.
          end,
        },
        sources = {
          { name = "nvim_lsp" },
          { name = "buffer" },
          { name = "codeium" },
          { name = "orgmode" },
        },
        mapping = cmp.mapping.preset.insert({
          ["<Tab>"] = cmp.mapping.select_next_item({ behavior = cmp.SelectBehavior.Insert }),
          ["<S-Tab>"] = cmp.mapping.select_prev_item({ behavior = cmp.SelectBehavior.Insert }),
          ["<C-b>"] = cmp.mapping.scroll_docs(-4),
          ["<C-f>"] = cmp.mapping.scroll_docs(4),
          ["<C-Space>"] = cmp.mapping.complete(),
          ["<C-e>"] = cmp.mapping.abort(),
          ["<CR>"] = cmp.mapping.confirm({ select = true }),
        }),
      })
    end,
  },

  -- LSP
  {
    "neovim/nvim-lspconfig",
    cmd = { "LspInfo", "LspInstall", "LspStart" },
    event = { "BufReadPre", "BufNewFile" },
    dependencies = {
      { "hrsh7th/cmp-nvim-lsp" },
      {
        "williamboman/mason-lspconfig.nvim",
        config = function()
          require("mason-lspconfig").setup({
            ensure_installed = ensure_installed,
          })
        end,
      },
    },
    lazy = false,
    config = function()
      vim.keymap.set({ "n" }, "<leader>ca", vim.lsp.buf.code_action, {
        desc = "Code Action.",
      })
      vim.keymap.set({ "n", "x" }, "<leader>cr", vim.lsp.buf.rename, {
        desc = "Rename.",
      })
      vim.keymap.set({ "n", "x" }, "<leader>ch", vim.lsp.buf.hover, {
        desc = "Hover definition.",
      })
      vim.keymap.set({ "n", "x" }, "<leader>ci", vim.lsp.buf.implementation, {
        desc = "Implementation.",
      })
      vim.keymap.set({ "n", "x" }, "<leader>ct", vim.lsp.buf.type_definition, {
        desc = "Type definition.",
      })
      vim.keymap.set({ "n", "x" }, "<leader>cd", vim.lsp.buf.definition, {
        desc = "Definition.",
      })
      vim.keymap.set({ "n", "x" }, "<leader>cs", vim.lsp.buf.signature_help, {
        desc = "Signature Help.",
      })
      vim.keymap.set({ "n", "x" }, "<leader>cf", function()
        vim.lsp.buf.format({ async = false, timeout = 3000 })
      end, {
        desc = "Format buffer LSP.",
      })

      vim.keymap.set({ "n", "x" }, "<leader>cF", "<Esc>mhgg=G'h", { desc = "Format buffer." })

      local capabilities = require("cmp_nvim_lsp").default_capabilities()
      local lspconfig = require("lspconfig")
      for _, lsp_name in ipairs(ensure_installed) do
        lspconfig[lsp_name].setup({
          capabilities = capabilities,
        })
      end
    end,
  },
}
