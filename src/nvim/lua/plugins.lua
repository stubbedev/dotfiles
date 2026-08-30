
vim.pack.add({
  { src = "https://github.com/catppuccin/nvim", name = "catppuccin" },

  { src = "https://github.com/saghen/blink.lib" },
  { src = "https://github.com/saghen/blink.cmp", version = vim.version.range("1") },

  { src = "https://github.com/stevearc/oil.nvim" },
  { src = "https://github.com/refractalize/oil-git-status.nvim" },
  { src = "https://github.com/nvim-tree/nvim-web-devicons" },
  { src = "https://github.com/chrisgrieser/nvim-recorder" },
  { src = "https://github.com/windwp/nvim-ts-autotag" },
}, { confirm = false })



require("catppuccin").setup({
  flavour = "mocha",
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

  local res = vim
    .system({ "git", "-C", dir, "check-ignore", "--stdin" }, { stdin = table.concat(names, "\n") .. "\n", text = true })
    :wait()
  for line in (res.stdout or ""):gmatch("[^\r\n]+") do
    set[line] = true
  end
  return set
end

vim.api.nvim_create_autocmd("User", {
  pattern = "OilActionsPost",
  group = vim.api.nvim_create_augroup("oil_ignore_cache", { clear = true }),
  callback = function()
    ignore_cache = {}
  end,
})

require("oil").setup({
  win_options = { signcolumn = "yes:2" },
  keymaps = {
    ["<leader>e"] = "actions.close",
    ["~"] = { "actions.cd", opts = { scope = "tab" }, mode = "n" },
  },
  view_options = {
    show_hidden = true,
    is_always_hidden = function(name, bufnr)
      local dir = require("oil").get_current_dir(bufnr)
      return dir ~= nil and ignored_in(dir)[name] == true
    end,
  },
})
require("oil-git-status").setup()


require("nvim-ts-autotag").setup()

require("recorder").setup({
  slots = { "a", "b", "c" },
  dynamicSlots = "rotate",
  lessNotifications = true,
  mapping = { addBreakPoint = "^^" },
})


require("blink.cmp").setup({
  enabled = function()
    return vim.bo.filetype ~= "grug-far"
  end,
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
})

vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
  pattern = "Cargo.toml",
  once = true,
  group = vim.api.nvim_create_augroup("crates_lazy", { clear = true }),
  callback = function()
    require("crates").setup({ completion = { crates = { enabled = true } } })
  end,
})

vim.api.nvim_create_autocmd("UIEnter", {
  once = true,
  callback = function()
    vim.schedule(function()
      vim.pack.add({
        { src = "https://github.com/ibhagwan/fzf-lua" },
        { src = "https://github.com/jake-stewart/multicursor.nvim", version = "1.0" },
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

      require("lazydev").setup({
        library = { { path = "${3rd}/luv/library", words = { "vim%.uv" } } },
      })
      require("format").setup()
      require("multicursor_keymaps")

      require("which-key").setup({
        preset = "classic",
        win = { no_overlap = false },
      })

      require("nvim-autopairs").setup({
        check_ts = true,
        fast_wrap = {},
      })

      require("auto-session").setup({
        auto_restore = false, -- restoring on every `nvim` in a repo is surprising
        suppressed_dirs = { "~/", "~/Downloads", "/" },
        session_lens = { load_on_setup = false },
      })

      _G.GrugFarFloat = function()
        local width = math.floor(vim.o.columns * 0.85)
        local height = math.floor(vim.o.lines * 0.85)
        local scratch = vim.api.nvim_create_buf(false, true)
        vim.bo[scratch].bufhidden = "wipe"
        vim.api.nvim_open_win(scratch, true, {
          relative = "editor",
          width = width,
          height = height,
          row = math.floor((vim.o.lines - height) * 0.4),
          col = math.floor((vim.o.columns - width) / 2),
          border = "rounded",
          title = " search / replace ",
          title_pos = "center",
        })
      end

      require("grug-far").setup({
        engines = { astgrep = { path = "ast-grep" } },
        windowCreationCommand = "lua _G.GrugFarFloat()",
        keymaps = { close = { n = "<esc>" } },
      })
    end)
  end,
})
