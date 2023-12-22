local ensure_installed = {
  "bashls",
  "clangd",
  "neocmake",
  "cssls",
  "html",
  "dockerls",
  "gopls",
  "jsonls",
  "tsserver",
  "lua_ls",
  "marksman",
  "phpactor",
  "pyright",
  "rust_analyzer",
  "volar",
  "yamlls"
}
return {
  {
    'VonHeikemen/lsp-zero.nvim',
    branch = 'v3.x',
    lazy = true,
    config = false,
    init = function()
      -- Disable automatic setup, we are doing it manually
      vim.g.lsp_zero_extend_cmp = 0
      vim.g.lsp_zero_extend_lspconfig = 0
    end,
  },
  {
    'williamboman/mason.nvim',
    lazy = false,
    config = true,
  },

  -- Autocompletion
  {
    'hrsh7th/nvim-cmp',
    event = 'InsertEnter',
    dependencies = {
      {
        'L3MON4D3/LuaSnip',
      },
      {
        'nvim-lua/plenary.nvim'
      },
      {
        'Exafunction/codeium.nvim',
        event = 'BufEnter',
        opts = {}
      }
    },
    config = function()
      -- Here is where you configure the autocompletion settings.
      local lsp_zero = require('lsp-zero')
      lsp_zero.extend_cmp()

      -- And you can configure cmp even more, if you want to.
      local cmp = require('cmp')
      local cmp_action = lsp_zero.cmp_action()

      cmp.setup({
        formatting = lsp_zero.cmp_format(),
        sources = {
          { name = 'nvim_lsp' },
          { name = 'buffer' },
          { name = 'codeium' },
        },
        mapping = cmp.mapping.preset.insert({
          ['<Tab>'] = cmp.mapping.select_next_item({ behavior = cmp.SelectBehavior.Insert }),
          ['<S-Tab>'] = cmp.mapping.select_prev_item({ behavior = cmp.SelectBehavior.Insert }),
          ['<CR>'] = cmp.mapping.confirm({ select = true }),
          ['<C-f>'] = cmp_action.luasnip_jump_forward(),
          ['<C-b>'] = cmp_action.luasnip_jump_backward(),
        })
      })
    end
  },

  -- LSP
  {
    'neovim/nvim-lspconfig',
    cmd = { 'LspInfo', 'LspInstall', 'LspStart' },
    event = { 'BufReadPre', 'BufNewFile' },
    dependencies = {
      { 'hrsh7th/cmp-nvim-lsp' },
      { 'williamboman/mason-lspconfig.nvim' },
    },
    config = function()
      local lsp_zero = require('lsp-zero')
      lsp_zero.extend_lspconfig()

      lsp_zero.on_attach(function(client, bufnr)
        lsp_zero.default_keymaps({ buffer = bufnr })
        local opts = { buffer = bufnr}

        vim.keymap.set({ 'n' }, '<leader>ca', vim.lsp.buf.code_action, {})
        vim.keymap.set({'n', 'x'}, '<leader>cf', function()
          vim.lsp.buf.format({
            async = false,
            timeout_ms = 10000,
          })
        end, opts)
      end)

      lsp_zero.set_sign_icons({
        error = '✘',
        warn = '▲',
        hint = '⚑',
        info = '»'
      })

      require('mason-lspconfig').setup({
        ensure_installed = ensure_installed,
        handlers = {
          lsp_zero.default_setup
        }
      })

      local lspconfig = require("lspconfig")
      for _, lsp_name in ipairs(ensure_installed) do
        lspconfig[lsp_name].setup({})
      end

    end
  }
}


