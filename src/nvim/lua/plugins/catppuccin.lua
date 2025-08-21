return {
  {
    "catppuccin/nvim",
    name = "catppuccin",
    priority = 1000,
    opts = {
      flavour = "mocha", -- latte, frappe, macchiato, mocha
      default_integrations = true,
      transparent_background = true,
      integrations = {
        aerial = true,
        alpha = true,
        cmp = true,
        blink_cmp = true,
        dashboard = true,
        flash = false,
        grug_far = true,
        overseer = true,
        gitsigns = true,
        headlines = true,
        illuminate = true,
        indent_blankline = { enabled = true },
        leap = true,
        lsp_trouble = true,
        dap = true,
        harpoon = true,
        mason = true,
        markdown = true,
        mini = true,
        native_lsp = {
          enabled = true,
          underlines = {
            errors = { "undercurl" },
            hints = { "undercurl" },
            warnings = { "undercurl" },
            information = { "undercurl" },
          },
        },
        navic = { enabled = true, custom_bg = "lualine" },
        neotest = true,
        neotree = false,
        noice = true,
        notify = true,
        semantic_tokens = true,
        telescope = true,
        snacks = {
          enabled = true,
        },
        treesitter = true,
        treesitter_context = true,
        which_key = true,
      },
    },
    specs = {
      {
        "akinsho/bufferline.nvim",
        optional = true,
        opts = function(_, opts)
          if (vim.g.colors_name or ""):find("catppuccin") then
            local ok, bufferline = pcall(require, "catppuccin.groups.integrations.bufferline")
            if ok and bufferline then
              opts.highlights = bufferline.get()
            end
          end
        end,
      },
    }
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "catppuccin",
    },
  },
}
