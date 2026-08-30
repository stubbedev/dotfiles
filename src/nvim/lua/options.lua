-- Editor options. Everything here used to be set invisibly by LazyVim; the
-- point of writing it out is that nothing is in effect that isn't on this page.

vim.g.mapleader = " "
vim.g.maplocalleader = " "

local o = vim.opt

-- Files and undo
o.undofile = true
o.undolevels = 10000
o.autowrite = true
o.confirm = true -- ask instead of failing when quitting with unsaved changes
o.swapfile = false
o.sessionoptions = { "buffers", "curdir", "tabpages", "winsize", "folds" }

-- Editing
o.expandtab = true
o.shiftwidth = 2
o.tabstop = 2
o.shiftround = true
o.smartindent = true
o.linebreak = true
o.formatoptions = "jcroqlnt"
o.virtualedit = "block"
o.completeopt = "menu,menuone,noselect"

-- Search
o.ignorecase = true
o.smartcase = true
o.inccommand = "nosplit" -- live preview of :s
o.grepprg = "rg --vimgrep"
o.grepformat = "%f:%l:%c:%m"

-- UI
o.termguicolors = true
o.number = true
o.relativenumber = true
o.cursorline = true
o.signcolumn = "yes"
o.scrolloff = 4
o.sidescrolloff = 8
o.smoothscroll = true
o.showmode = false -- the statusline already says the mode
o.ruler = false
o.pumheight = 10
o.pumblend = 10
o.conceallevel = 2
o.list = true
o.fillchars = { foldopen = "▾", foldclose = "▸", fold = " ", eob = " ", diff = "╱" }
o.splitbelow = true
o.splitright = true
o.splitkeep = "screen"
o.laststatus = 3 -- one global statusline, not one per window
-- The command line is an empty row under the statusline whenever it isn't
-- being typed into. Neovim reclaims it on demand, so nothing is lost.
o.cmdheight = 0
o.showtabline = 1 -- tabline only when lua/statusline.lua says there's something to show
o.shortmess:append({ W = true, I = true, c = true, C = true })
o.timeoutlen = 300
o.updatetime = 200
o.jumpoptions = "view"
o.spelllang = { "en" }

-- Folds come from treesitter; start fully open.
o.foldlevel = 99
o.foldmethod = "expr"
o.foldexpr = "v:lua.vim.treesitter.foldexpr()"
o.foldtext = ""

-- Mouse off: this is a keyboard editor, and a stray trackpad touch moving the
-- cursor mid-edit is worse than any convenience it buys.
o.mouse = ""

o.clipboard = vim.env.SSH_CONNECTION and "" or "unnamedplus"

-- Load project-local .nvim.lua/.nvimrc/.exrc from nvim's launch dir for
-- per-project config (post-save hooks, etc.). Neovim prompts to :trust each
-- file before it runs, so only trust repos you control.
o.exrc = true

-- Filetypes ----------------------------------------------------------------

-- tmpl files are Go templates wrapping HTML; point both parsers at them.
vim.treesitter.language.register("html", { "html", "tmpl" })
vim.treesitter.language.register("templ", { "templ", "tmpl" })

-- Filetypes whose name doesn't match their parser. Without these,
-- vim.treesitter.start() looks for a "typescriptreact"/"sh"/"jsonc" parser,
-- finds nothing, and the buffer silently falls back to regex syntax.
vim.treesitter.language.register("tsx", { "typescriptreact" })
vim.treesitter.language.register("javascript", { "javascriptreact" })
vim.treesitter.language.register("bash", { "sh", "zsh" })
vim.treesitter.language.register("json", { "jsonc" })

vim.filetype.add({
  extension = { caddy = "caddy" },
  filename = {
    Caddyfile = "caddy",
    -- The compose language server only attaches to this compound filetype.
    ["docker-compose.yml"] = "yaml.docker-compose",
    ["docker-compose.yaml"] = "yaml.docker-compose",
    ["compose.yml"] = "yaml.docker-compose",
    ["compose.yaml"] = "yaml.docker-compose",
  },
})

-- Appearance ---------------------------------------------------------------

-- GUI font (read by neovide, ignored by terminal nvim). Mirrors
-- modules/terminal.nix so neovide and alacritty render the same.
vim.o.guifont = "JetBrainsMono Nerd Font:h12"

if vim.g.neovide then
  -- Neovide blends glyphs gamma-corrected, so the same catppuccin hexes look
  -- washed out next to alacritty. Values from neovide's docs for emulating
  -- alacritty's font rendering.
  vim.g.neovide_text_gamma = 0.8
  vim.g.neovide_text_contrast = 0.1
end

-- :terminal ANSI palette. catppuccin ships term_colors = false, so without
-- this nvim's builtin terminal falls back to the default ANSI colors -- fine
-- under alacritty (its own palette wins), wrong under neovide. Values are
-- modules/terminal.nix verbatim; catppuccin-nvim's own mapping picks
-- different shades for 0/6/7/8/15.
for i, color in ipairs({
  "#45475a",
  "#f38ba8",
  "#a6e3a1",
  "#f9e2af", -- black red green yellow
  "#89b4fa",
  "#f5c2e7",
  "#94e2d5",
  "#bac2de", -- blue magenta cyan white
  "#585b70",
  "#f38ba8",
  "#a6e3a1",
  "#f9e2af", -- bright black red green yellow
  "#89b4fa",
  "#f5c2e7",
  "#94e2d5",
  "#a6adc8", -- bright blue magenta cyan white
}) do
  vim.g["terminal_color_" .. (i - 1)] = color
end

-- Diagnostics --------------------------------------------------------------

vim.diagnostic.config({
  severity_sort = true,
  underline = true,
  update_in_insert = false,
  virtual_text = { spacing = 4, source = "if_many" },
  signs = {
    -- Nerd Font glyphs as \u escapes: written literally they get mangled by
    -- some editors and tooling, and a stripped glyph is an invisible sign.
    text = {
      [vim.diagnostic.severity.ERROR] = "\u{f057} ",
      [vim.diagnostic.severity.WARN] = "\u{f071} ",
      [vim.diagnostic.severity.INFO] = "\u{f05a} ",
      [vim.diagnostic.severity.HINT] = "\u{f0eb} ",
    },
  },
  float = { border = "rounded", source = "if_many" },
})
