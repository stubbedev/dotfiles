return {
  "folke/snacks.nvim",
  opts = {
    picker = {
      sources = {
        -- Configure files picker to respect .gitignore by default
        files = {
          ignored = false, -- don't show ignored files (respects .gitignore)
          hidden = false,  -- don't show hidden files
        },
        -- Configure grep to respect .gitignore by default
        grep = {
          ignored = false, -- don't show ignored files (respects .gitignore)
          hidden = false,  -- don't show hidden files
        },
        -- Configure git_grep to respect .gitignore (this is the default anyway)
        git_grep = {
          ignored = false,
          hidden = false,
        },
        -- Configure explorer to respect .gitignore by default
        explorer = {
          ignored = false,
          hidden = false,
        },
      },
    },
    explorer = {
      enabled = false,
    },
  },
}
