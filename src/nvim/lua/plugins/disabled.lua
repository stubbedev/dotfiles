return {
  -- Mason can't run on NixOS (downloads pre-built binaries that miss the
  -- FHS dynamic linker). LSPs/formatters/linters live in the nix wrapper
  -- PATH instead — see modules/programs/nvim/_wrapper.nix.
  { "mason-org/mason.nvim",            enabled = false },
  { "mason-org/mason-lspconfig.nvim",  enabled = false },
  { "jay-babu/mason-nvim-dap.nvim",    enabled = false },

  -- Browser preview of markdown, and it pulls a node build step. The rest of
  -- the lang.markdown extra stays: render-markdown draws it in the buffer and
  -- marksman is the LSP.
  { "iamcco/markdown-preview.nvim",    enabled = false },

  { "nvim-mini/mini.indentscope",      enabled = false },
  { "goolord/alpha-nvim",              enabled = false },
  { "akinsho/bufferline.nvim",         enabled = false },
  {
    "folke/snacks.nvim",
    keys = {
      { "<c-/>",      false },
      { "<c-_>",      false },
      { "<leader>e",  false },
      { "<leader>E",  false },
      { "<leader>fe", false },
      { "<leader>fE", false },
    },
    opts = {
      terminal = { enabled = false },
      explorer = { enabled = false },
      scroll = { enabled = false },
      indent = {
        enabled = false,
        scope = {
          enabled = false,
        }
      },
      dashboard = {
        preset = {
          header = [[
███████╗████████╗██╗   ██╗██████╗ ██████╗ ███████╗
██╔════╝╚══██╔══╝██║   ██║██╔══██╗██╔══██╗██╔════╝
███████╗   ██║   ██║   ██║██████╔╝██████╔╝█████╗  
╚════██║   ██║   ██║   ██║██╔══██╗██╔══██╗██╔══╝  
███████║   ██║   ╚██████╔╝██████╔╝██████╔╝███████╗
╚══════╝   ╚═╝    ╚═════╝ ╚═════╝ ╚═════╝ ╚══════╝]]
        }
      }
    }
  },
}
