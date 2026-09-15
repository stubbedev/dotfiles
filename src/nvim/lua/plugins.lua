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
  keymap = { preset = "default" },
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
        { src = "https://github.com/nvim-lua/plenary.nvim" },
        { src = "https://github.com/folke/flash.nvim" },
        { src = "https://github.com/folke/trouble.nvim" },
        { src = "https://github.com/folke/todo-comments.nvim" },
        { src = "https://github.com/nvim-mini/mini.ai" },
        { src = "https://github.com/nvim-mini/mini.surround" },
        { src = "https://github.com/nvim-treesitter/nvim-treesitter-textobjects", version = "main" },
        { src = "https://github.com/monaqa/dial.nvim" },
        { src = "https://github.com/MunifTanjim/nui.nvim" },
        { src = "https://github.com/folke/noice.nvim" },
        { src = "https://github.com/nvim-lualine/lualine.nvim" },
      }, { confirm = false })

      vim.cmd("doautoall FileType")

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
            layout = "vertical",
            vertical = "down:55%",
            scrollbar = "float",
          },
        },
        keymap = {
          builtin = {
            ["<C-j>"] = "preview-down",
            ["<C-k>"] = "preview-up",
            ["<C-Down>"] = "preview-down",
            ["<C-Up>"] = "preview-up",
          },
        },
        fzf_opts = {
          ["--info"] = "inline-right",
          ["--layout"] = "reverse",
          ["--pointer"] = "",
          ["--marker"] = "",
        },
        defaults = { headers = false },
        files = {
          cwd_prompt = false,
          prompt = "  ",
          git_icons = true,
        },
        git = { files = { prompt = "  " } },
        oldfiles = { prompt = "  " },
        buffers = { prompt = "  " },
        helptags = { prompt = "  " },
        keymaps = { prompt = "  " },
        diagnostics = { prompt = "  " },
        grep = { prompt = "  " },
        lsp = { symbols = { prompt = "  " } },
      })

      require("treesitter-context").setup({ max_lines = 3, mode = "cursor" })

      require("gitsigns").setup({
        on_attach = function(buf)
          local gs = require("gitsigns")
          local function map(mode, lhs, rhs, desc)
            vim.keymap.set(mode, lhs, rhs, { buffer = buf, desc = desc, silent = true })
          end

          map("n", "]h", function()
            if vim.wo.diff then
              vim.cmd.normal({ "]c", bang = true })
            else
              gs.nav_hunk("next")
            end
          end, "Next hunk")
          map("n", "[h", function()
            if vim.wo.diff then
              vim.cmd.normal({ "[c", bang = true })
            else
              gs.nav_hunk("prev")
            end
          end, "Prev hunk")
          map("n", "]H", function()
            gs.nav_hunk("last")
          end, "Last hunk")
          map("n", "[H", function()
            gs.nav_hunk("first")
          end, "First hunk")

          map({ "n", "x" }, "<leader>ghs", ":Gitsigns stage_hunk<cr>", "Stage hunk")
          map({ "n", "x" }, "<leader>ghr", ":Gitsigns reset_hunk<cr>", "Reset hunk")
          map("n", "<leader>ghS", gs.stage_buffer, "Stage buffer")
          map("n", "<leader>ghu", gs.undo_stage_hunk, "Undo stage hunk")
          map("n", "<leader>ghR", gs.reset_buffer, "Reset buffer")
          map("n", "<leader>ghp", gs.preview_hunk_inline, "Preview hunk inline")
          map("n", "<leader>ghb", function()
            gs.blame_line({ full = true })
          end, "Blame line")
          map("n", "<leader>ghB", function()
            gs.blame()
          end, "Blame buffer")
          map("n", "<leader>ghd", gs.diffthis, "Diff this")
          map("n", "<leader>ghD", function()
            gs.diffthis("~")
          end, "Diff this ~")
          map({ "o", "x" }, "ih", ":<C-U>Gitsigns select_hunk<cr>", "Select hunk")
        end,
      })

      require("lazydev").setup({
        library = { { path = "${3rd}/luv/library", words = { "vim%.uv" } } },
      })

      require("noice").setup({
        presets = {
          bottom_search = true, -- keep / and :s at the cmdline like LazyVim
          command_palette = true, -- : commands in a centered floating box
          long_message_to_split = true,
        },
        lsp = {
          -- hover/signature are handled by lsp.lua and blink.cmp already
          override = {},
          hover = { enabled = false },
          signature = { enabled = false },
        },
      })

      require("statusline").setup_lualine()
      require("format").setup()

      local textobjects = {
        { "a", desc = "argument" },
        { "b", desc = "balanced )]}" },
        { "c", desc = "class" },
        { "d", desc = "digit(s)" },
        { "e", desc = "word in CamelCase/snake_case" },
        { "f", desc = "function" },
        { "g", desc = "entire buffer" },
        { "h", desc = "git hunk" },
        { "o", desc = "block/conditional/loop" },
        { "q", desc = "quote `\"'" },
        { "t", desc = "tag" },
        { "u", desc = "use/call function" },
        { "U", desc = "use/call without dot" },
      }

      local function textobject_spec(prefix, name)
        local spec = { prefix, group = name, mode = { "o", "x" } }
        for _, object in ipairs(textobjects) do
          table.insert(spec, { prefix .. object[1], desc = object.desc, mode = { "o", "x" } })
        end
        return spec
      end

      require("which-key").setup({
        preset = "classic",
        win = { no_overlap = false },
        spec = {
          {
            mode = { "n", "x" },
            { "<leader><tab>", group = "tabs" },
            { "<leader>b", group = "buffer" },
            { "<leader>c", group = "code" },
            { "<leader>f", group = "file/find" },
            { "<leader>g", group = "git" },
            { "<leader>l", group = "plugins" },
            { "<leader>gh", group = "hunks" },
            { "<leader>q", group = "quit/session" },
            { "<leader>r", group = "replace" },
            { "<leader>s", group = "search" },
            { "<leader>u", group = "ui/toggle" },
            { "<leader>w", group = "windows", proxy = "<c-w>" },
            { "<leader>x", group = "diagnostics/quickfix" },
            { "[", group = "prev" },
            { "]", group = "next" },
            { "g", group = "goto" },
            { "gc", group = "comment" },
            { "gs", group = "surround" },
            { "z", group = "fold" },
            { "gx", desc = "Open with system app" },
            { "<leader>`", desc = "Switch to other buffer" },
            { "<leader>|", desc = "Split window right" },
            { "<leader>-", desc = "Split window below" },
            { "<leader>.", desc = "Toggle scratch buffer" },
            { "<leader>,", desc = "Buffers" },
            { "<leader>/", desc = "Grep" },
            { "<leader>:", desc = "Command history" },
            { "<leader><space>", desc = "Find files" },
          },
          textobject_spec("a", "around"),
          textobject_spec("i", "inside"),
        },
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
        engines = {
          ripgrep = { placeholders = { enabled = false } },
          astgrep = { path = "ast-grep", placeholders = { enabled = false } },
          ["astgrep-rules"] = { placeholders = { enabled = false } },
        },
        windowCreationCommand = "lua _G.GrugFarFloat()",
        keymaps = { close = { n = "<esc>" } },
        -- one line per input instead of label-above-field: 6 header lines
        -- instead of 15, so results start near the top. Help line stays.
        showCompactInputs = true,
        showInputsTopPadding = false,
        showInputsBottomPadding = false,
      })

      require("flash").setup()

      local flash = function(fn, opts)
        return function()
          require("flash")[fn](opts)
        end
      end
      vim.keymap.set({ "n", "x", "o" }, "s", flash("jump"), { desc = "Flash" })
      vim.keymap.set({ "n", "x", "o" }, "S", flash("treesitter"), { desc = "Flash treesitter" })
      vim.keymap.set("o", "r", flash("remote"), { desc = "Remote flash" })
      vim.keymap.set({ "o", "x" }, "R", flash("treesitter_search"), { desc = "Treesitter search" })
      vim.keymap.set("c", "<c-s>", flash("toggle"), { desc = "Toggle flash search" })

      require("trouble").setup({
        modes = { lsp = { win = { position = "right" } } },
      })

      require("todo-comments").setup()
      vim.keymap.set("n", "]t", function()
        require("todo-comments").jump_next()
      end, { desc = "Next todo comment" })
      vim.keymap.set("n", "[t", function()
        require("todo-comments").jump_prev()
      end, { desc = "Prev todo comment" })

      local ai = require("mini.ai")
      ai.setup({
        n_lines = 500,
        custom_textobjects = {
          o = ai.gen_spec.treesitter({
            a = { "@block.outer", "@conditional.outer", "@loop.outer" },
            i = { "@block.inner", "@conditional.inner", "@loop.inner" },
          }),
          f = ai.gen_spec.treesitter({ a = "@function.outer", i = "@function.inner" }),
          c = ai.gen_spec.treesitter({ a = "@class.outer", i = "@class.inner" }),
          a = ai.gen_spec.treesitter({ a = "@parameter.outer", i = "@parameter.inner" }),
          t = { "<([%p%w]-)%f[^<%w][^<>]->.-</%1>", "^<.->().*()</[^/]->$" },
          d = { "%f[%d]%d+" },
          e = {
            { "%u[%l%d]+%f[^%l%d]", "%f[%S][%l%d]+%f[^%l%d]", "%f[%P][%l%d]+%f[^%l%d]", "^[%l%d]+%f[^%l%d]" },
            "^().*()$",
          },
          g = function()
            local last = vim.fn.line("$")
            return {
              from = { line = 1, col = 1 },
              to = { line = last, col = math.max(vim.fn.getline(last):len(), 1) },
            }
          end,
          u = ai.gen_spec.function_call(),
          U = ai.gen_spec.function_call({ name_pattern = "[%w_]" }),
        },
      })

      require("mini.surround").setup({
        mappings = {
          add = "gsa",
          delete = "gsd",
          find = "gsf",
          find_left = "gsF",
          highlight = "gsh",
          replace = "gsr",
          update_n_lines = "gsn",
        },
      })

      require("nvim-treesitter-textobjects").setup({ move = { set_jumps = true } })

      local ts_moves = {
        goto_next_start = { ["]f"] = "@function.outer", ["]c"] = "@class.outer", ["]a"] = "@parameter.inner" },
        goto_next_end = { ["]F"] = "@function.outer", ["]C"] = "@class.outer", ["]A"] = "@parameter.inner" },
        goto_previous_start = { ["[f"] = "@function.outer", ["[c"] = "@class.outer", ["[a"] = "@parameter.inner" },
        goto_previous_end = { ["[F"] = "@function.outer", ["[C"] = "@class.outer", ["[A"] = "@parameter.inner" },
      }

      local function attach_textobjects(buf)
        local lang = vim.treesitter.language.get_lang(vim.bo[buf].filetype)
        local ok, query = pcall(vim.treesitter.query.get, lang, "textobjects")
        if not lang or not ok or not query then
          return
        end
        for method, keys in pairs(ts_moves) do
          for key, query in pairs(keys) do
            local object = query:gsub("@", ""):gsub("%..*", "")
            local desc = (key:sub(1, 1) == "[" and "Prev " or "Next ")
              .. object:sub(1, 1):upper()
              .. object:sub(2)
              .. (key:sub(2, 2) == key:sub(2, 2):upper() and " end" or " start")
            vim.keymap.set({ "n", "x", "o" }, key, function()
              if vim.wo.diff and key:find("[cC]") then
                return vim.cmd("normal! " .. key)
              end
              require("nvim-treesitter-textobjects.move")[method](query, "textobjects")
            end, { buffer = buf, desc = desc, silent = true })
          end
        end
      end

      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("treesitter_textobjects", { clear = true }),
        callback = function(args)
          attach_textobjects(args.buf)
        end,
      })
      vim.tbl_map(attach_textobjects, vim.api.nvim_list_bufs())

      require("dial_config").setup()
    end)
  end,
})
