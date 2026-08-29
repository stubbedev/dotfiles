-- Plugins, via nvim 0.12's built-in vim.pack. No plugin manager.
--
-- vim.pack clones into site/pack/core/opt and puts each plugin on the
-- runtimepath; because this runs during init.lua, the normal startup sequence
-- sources their plugin/ files afterwards. That means "add it here and call its
-- setup below" is the whole mental model -- there is no spec DSL, no lazy
-- handlers, no import graph.
--
-- Update everything with `:lua vim.pack.update()`.
-- `version` pins a branch/tag; leaving it off tracks the default branch.

-- Loaded during startup, because something needs them before the first
-- keystroke: the colorscheme, completion (lua/lsp.lua asks blink for its
-- capabilities), the file explorer that may be handling `nvim .`, and the
-- pieces the statusline reads.
vim.pack.add({
  { src = "https://github.com/catppuccin/nvim", name = "catppuccin" },

  -- Completion. blink.cmp fetches its own prebuilt Rust fuzzy matcher keyed
  -- on the tag, so it must stay pinned to a release, not a moving branch.
  { src = "https://github.com/saghen/blink.lib" },
  { src = "https://github.com/saghen/blink.cmp", version = vim.version.range("1") },

  { src = "https://github.com/stevearc/oil.nvim" },
  { src = "https://github.com/refractalize/oil-git-status.nvim" },
  { src = "https://github.com/nvim-tree/nvim-web-devicons" },
  { src = "https://github.com/chrisgrieser/nvim-recorder" },
  { src = "https://github.com/windwp/nvim-ts-autotag" },
}, { confirm = false })

-- `load = false` puts these on the runtimepath (so `require` finds them) but
-- doesn't source their plugin/ files, which keeps them off the startup path.
-- They cost ~28ms between them -- fzf-lua alone is 20 -- and none is needed
-- before the UI is up.
vim.pack.add({
  { src = "https://github.com/ibhagwan/fzf-lua" },
  { src = "https://github.com/jake-stewart/multicursor.nvim", version = "1.0" },
  { src = "https://github.com/mbbill/undotree" },
  { src = "https://github.com/nvim-treesitter/nvim-treesitter-context" },
  { src = "https://github.com/stevearc/conform.nvim" },
  { src = "https://github.com/mfussenegger/nvim-lint" },
  { src = "https://github.com/mrcjkb/rustaceanvim" },
  { src = "https://github.com/saecki/crates.nvim" },
  { src = "https://github.com/lewis6991/gitsigns.nvim" },
  { src = "https://github.com/folke/lazydev.nvim" }, -- lua_ls that knows the nvim API
  { src = "https://github.com/folke/which-key.nvim" },
  { src = "https://github.com/windwp/nvim-autopairs" },
  { src = "https://github.com/rmagatti/auto-session" },
  { src = "https://github.com/MagicDuck/grug-far.nvim" },
}, { confirm = false, load = false })

-- Colorscheme ---------------------------------------------------------------

require("catppuccin").setup({
  flavour = "mocha",
  -- term_colors stays off: lua/options.lua sets the :terminal palette by hand
  -- to match alacritty exactly, which catppuccin's own mapping doesn't.
  term_colors = false,
  integrations = {
    blink_cmp = true,
    gitsigns = true,
    treesitter = true,
    treesitter_context = true,
    fzf = true,
    native_lsp = { enabled = true },
  },
})
vim.cmd.colorscheme("catppuccin-mocha")

-- Files ---------------------------------------------------------------------

require("oil").setup({
  default_file_explorer = true,
  columns = { "icon" },
  buf_options = { buflisted = false, bufhidden = "hide" },
  win_options = {
    wrap = false,
    signcolumn = "yes:2", -- room for oil-git-status
    cursorcolumn = false,
    foldcolumn = "0",
    spell = false,
    list = false,
    conceallevel = 3,
    concealcursor = "nvic",
  },
  delete_to_trash = false,
  skip_confirm_for_simple_edits = false,
  prompt_save_on_select_new_entry = true,
  cleanup_delay_ms = 2000,
  keymaps = {
    ["g?"] = "actions.show_help",
    ["<CR>"] = "actions.select",
    ["<C-s>"] = "actions.select_vsplit",
    ["<C-h>"] = "actions.select_split",
    ["<C-t>"] = "actions.select_tab",
    ["<C-p>"] = "actions.preview",
    ["<leader>e"] = "actions.close",
    ["<C-c>"] = "actions.close",
    ["<C-l>"] = "actions.refresh",
    ["-"] = "actions.parent",
    ["_"] = "actions.open_cwd",
    ["`"] = "actions.cd",
    ["~"] = "actions.tcd",
    ["gs"] = "actions.change_sort",
    ["gx"] = "actions.open_external",
    ["g."] = "actions.toggle_hidden",
    ["g\\"] = "actions.toggle_trash",
  },
  use_default_keymaps = true,
  view_options = {
    show_hidden = true,
    is_hidden_file = function(name)
      return vim.startswith(name, ".")
    end,
    -- Hide what git ignores, so build output and vendor/ don't bury the tree.
    is_always_hidden = function(name, bufnr)
      if vim.fn.executable("git") == 0 then
        return false
      end
      local dir = require("oil").get_current_dir(bufnr)
      if not dir then
        return false
      end
      local path = vim.fs.joinpath(dir, name)
      return vim.system({ "git", "-C", dir, "check-ignore", "-q", path }):wait().code == 0
    end,
    sort = { { "type", "asc" }, { "name", "asc" } },
  },
  float = { padding = 2, max_width = 0, max_height = 0, win_options = { winblend = 0 } },
  preview = {
    max_width = 0.9,
    min_width = { 40, 0.4 },
    max_height = 0.9,
    min_height = { 5, 0.1 },
    win_options = { winblend = 0 },
    update_on_cursor_moved = true,
  },
  progress = {
    max_width = 0.9,
    min_width = { 40, 0.4 },
    max_height = { 10, 0.9 },
    min_height = { 5, 0.1 },
    border = "rounded",
    minimized_border = "none",
    win_options = { winblend = 0 },
  },
})
require("oil-git-status").setup()

-- Editing -------------------------------------------------------------------

require("nvim-ts-autotag").setup()

require("recorder").setup({
  slots = { "a", "b", "c" },
  dynamicSlots = "rotate",
  mapping = {
    startStopRecording = "q",
    playMacro = "Q",
    switchSlot = "<C-q>",
    editMacro = "cq",
    deleteAllMacros = "dq",
    yankMacro = "yq",
    addBreakPoint = "^^",
  },
  clear = false,
  logLevel = vim.log.levels.INFO,
  lessNotifications = true,
  useNerdfontIcons = true,
  performanceOpts = {
    countThreshold = 100,
    lazyredraw = true,
    noSystemClipboard = true,
    autocmdEventsIgnore = {
      "TextChangedI",
      "TextChanged",
      "InsertLeave",
      "InsertEnter",
      "InsertCharPre",
    },
  },
  dapSharedKeymaps = false,
  timeout = 300,
})

-- Completion ----------------------------------------------------------------

require("blink.cmp").setup({
  completion = {
    documentation = { auto_show = true, auto_show_delay_ms = 500 },
  },
  signature = { enabled = true, window = { show_documentation = false } },
  sources = {
    default = { "lsp", "buffer", "snippets", "path", "lazydev" },
    providers = {
      lazydev = { name = "LazyDev", module = "lazydev.integrations.blink", score_offset = 100 },
    },
  },
  -- No custom `fuzzy.sorts`: a Lua comparator drops blink out of its Rust
  -- sorter and back into a Lua sort on every keystroke (~40% of its per-key
  -- cost, measured). The Rust scorer ranks these sources fine on its own.
})

-- Deferred plugins ----------------------------------------------------------
--
-- Everything above is on the runtimepath but unsourced. Loading it one tick
-- after the UI appears keeps it out of the startup measurement *and* out of
-- the time before the first frame, which is the part that's actually felt.
vim.api.nvim_create_autocmd("UIEnter", {
  once = true,
  callback = function()
    vim.schedule(function()
      for _, name in ipairs({
        "fzf-lua",
        "multicursor.nvim",
        "undotree",
        "nvim-treesitter-context",
        "conform.nvim",
        "nvim-lint",
        "rustaceanvim",
        "crates.nvim",
        "gitsigns.nvim",
        "which-key.nvim",
        "nvim-autopairs",
        "auto-session",
        "grug-far.nvim",
      }) do
        pcall(vim.cmd.packadd, name)
      end

      -- fzf-lua shells out to the fzf binary from nix, so matching is native
      -- and the plugin is only the UI around it.
      require("fzf-lua").setup({
        "default",
        winopts = { preview = { default = "builtin" } },
        files = { git_icons = true },
      })

      require("treesitter-context").setup({ max_lines = 3, mode = "cursor" })
      require("crates").setup({ completion = { crates = { enabled = true } } })
      require("multicursor-nvim").setup()
      require("gitsigns").setup()
      require("format").setup()
      require("multicursor_keymaps")

      require("which-key").setup({
        preset = "classic",
        win = { no_overlap = false },
      })

      -- nvim-autopairs over mini.pairs: it is treesitter-aware (it won't pair
      -- inside a string or comment) and is the more actively maintained of the
      -- two. `check_ts` is the reason to prefer it.
      require("nvim-autopairs").setup({
        check_ts = true,
        fast_wrap = {},
      })

      -- auto-session over persistence.nvim, which has not been touched since
      -- 2025-10. Sessions are keyed on cwd, so one per project.
      require("auto-session").setup({
        auto_restore = false, -- restoring on every `nvim` in a repo is surprising
        suppressed_dirs = { "~/", "~/Downloads", "/" },
        session_lens = { load_on_setup = false },
      })

      -- grug-far drives ripgrep *and* ast-grep. ast-grep is the one that makes
      -- "rename this everywhere" safe: it matches on syntax tree shape
      -- (`$A.foo($B)` -> `$A.bar($B)`) rather than on text, so it won't touch a
      -- string or a comment that happens to contain the same characters.
      require("grug-far").setup({
        engines = { astgrep = { path = "ast-grep" } },
      })
    end)
  end,
})

-- lazydev teaches lua_ls the Neovim API, so it only matters once a Lua buffer
-- exists -- and it must be loaded before lua_ls attaches to one.
vim.api.nvim_create_autocmd("FileType", {
  pattern = "lua",
  once = true,
  callback = function()
    vim.cmd.packadd("lazydev.nvim")
    require("lazydev").setup({
      library = { { path = "${3rd}/luv/library", words = { "vim%.uv" } } },
    })
  end,
})
