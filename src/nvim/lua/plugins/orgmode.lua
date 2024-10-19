return {
  {
    "nvim-orgmode/orgmode",
    event = "VeryLazy",
    lazy = false,
    config = function()
      require("nvim-treesitter.configs").setup({
        highlight = {
          enable = true,
          additional_vim_regex_highlighting = { "org" },
        },
        ensure_installed = { "org" },
      })
      require("orgmode").setup({
        org_agenda_files = { "~/git/org-files/**/*" },
        org_default_notes_file = "~/git/org-files/refile.org",
        org_todo_keywords = { "TODO(t)", "|", "DONE(d)" },
        org_capture_templates = {
          t = {
            description = "Todo",
            template = "* TODO %?\n%U",
            target = "~/git/org-files/todo.org",
          },
          j = {
            description = "Journal",
            template = "\n*** %<%Y-%m-%d> %<%A>\n**** %U\n\n%?",
            target = "~/git/org-files/journal.org",
          },
          n = {
            description = "Notes",
            template = "* %?\n %u",
            target = "~/git/org-files/notes.org",
          },
        },
      })
    end,
  },
}
