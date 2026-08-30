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

-- The rest are registered from the post-UI hook at the bottom of this file,
-- not here. `vim.pack.add(..., { load = false })` is not enough on its own:
-- it skips sourcing the plugin at that moment, but the directory still lands
-- on the runtimepath, and Neovim's normal plugin pass then sources every
-- plugin/*.lua it finds there. gitsigns and nvim-treesitter-context require
-- their whole module from that file, so both were loading during startup
-- despite being "deferred".

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

-- Set of git-ignored names per directory, resolved with one `git check-ignore
-- --stdin` call for the whole directory. See is_always_hidden below.
local ignore_cache = {}

local function ignored_in(dir)
  local cached = ignore_cache[dir]
  if cached then
    return cached
  end

  local set = {}
  ignore_cache[dir] = set
  if vim.fn.executable("git") == 0 then
    return set
  end

  local names, scan = {}, vim.uv.fs_scandir(dir)
  if scan then
    while true do
      local name = vim.uv.fs_scandir_next(scan)
      if not name then
        break
      end
      names[#names + 1] = name
    end
  end
  if #names == 0 then
    return set
  end

  -- check-ignore exits 1 when nothing matches, which is not an error here.
  local res = vim
    .system({ "git", "-C", dir, "check-ignore", "--stdin" }, { stdin = table.concat(names, "\n") .. "\n", text = true })
    :wait()
  for line in (res.stdout or ""):gmatch("[^\r\n]+") do
    set[line] = true
  end
  return set
end

-- oil edits files, so a rename or delete can change what is ignored.
vim.api.nvim_create_autocmd("User", {
  pattern = "OilActionsPost",
  group = vim.api.nvim_create_augroup("oil_ignore_cache", { clear = true }),
  callback = function()
    ignore_cache = {}
  end,
})

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
    --
    -- oil asks this once per entry, so the obvious implementation -- one
    -- `git check-ignore` per name -- spawns a process per file. Measured on a
    -- 136-entry directory that was 136 spawns and 1818ms of blocked UI.
    -- Instead: scan the directory once (no process), ask git about every name
    -- in a single `--stdin` call, and cache the answer per directory.
    is_always_hidden = function(name, bufnr)
      local dir = require("oil").get_current_dir(bufnr)
      if not dir then
        return false
      end
      return (ignored_in(dir))[name] == true
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

-- crates.nvim's setup() installs global CursorMoved/CursorMovedI/TextChanged/
-- TextChangedI autocmds, which then run in every buffer -- a PHP file was
-- paying for them. The plugin is registered with the others above so
-- vim.pack.update() still sees it; only its setup is held back until there is
-- a Cargo.toml to act on.
vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
  pattern = "Cargo.toml",
  once = true,
  group = vim.api.nvim_create_augroup("crates_lazy", { clear = true }),
  callback = function()
    require("crates").setup({ completion = { crates = { enabled = true } } })
  end,
})

-- Deferred plugins ----------------------------------------------------------
--
-- Everything registered below is loaded one tick after the UI appears, so it
-- stays out of both the startup path and the time before the first frame,
-- which is the part that is actually felt.
vim.api.nvim_create_autocmd("UIEnter", {
  once = true,
  callback = function()
    vim.schedule(function()
      -- Registered here rather than during init.lua: after startup vim.pack
      -- defaults to loading what it adds, and nothing above has been on the
      -- runtimepath until now, so none of it touched the startup path.
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
      }, { confirm = false })

      -- fzf-lua shells out to the fzf binary from nix, so matching is native
      -- and the plugin is only the UI around it.
      -- Telescope-ish: centred float, rounded border, preview on the right.
      -- `cwd_prompt = false` is the one that matters day to day -- fzf-lua
      -- otherwise puts the whole cwd in front of the prompt, so you type your
      -- query after `~/g/w/k/.w/f/KON-13271-.../`.
      local fzf = require("fzf-lua")
      fzf.setup({
        fzf_colors = true, -- take colours from the colorscheme, not fzf's defaults
        winopts = {
          height = 0.85,
          width = 0.85,
          row = 0.4,
          border = "rounded",
          backdrop = 100, -- no dimming; catppuccin is dark enough
          preview = {
            default = "builtin",
            border = "rounded",
            layout = "flex",
            horizontal = "right:55%",
            scrollbar = "float",
          },
        },
        fzf_opts = { ["--info"] = "inline-right", ["--layout"] = "reverse" },
        files = {
          cwd_prompt = false,
          prompt = "Files  ",
          git_icons = true,
        },
        grep = { prompt = "Grep  " },
        buffers = { prompt = "Buffers  " },
      })

      require("treesitter-context").setup({ max_lines = 3, mode = "cursor" })
      require("multicursor-nvim").setup()
      require("gitsigns").setup()

      -- lazydev teaches lua_ls about the Neovim API. It has to be loaded
      -- before lua_ls attaches to a Lua buffer, which UIEnter comfortably is.
      require("lazydev").setup({
        library = { { path = "${3rd}/luv/library", words = { "vim%.uv" } } },
      })
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
