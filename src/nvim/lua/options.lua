
vim.g.mapleader = " "
vim.g.maplocalleader = " "

for _, plugin in ipairs({
  "gzip",
  "matchit",
  "matchparen",
  "netrw",
  "netrwPlugin",
  "netrwSettings",
  "netrwFileHandlers",
  "tar",
  "tarPlugin",
  "zip",
  "zipPlugin",
  "2html_plugin",
  "tutor_mode_plugin",
  "rrhelper",
  "vimball",
  "vimballPlugin",
}) do
  vim.g["loaded_" .. plugin] = 1
end

local o = vim.opt

o.undofile = true
o.undolevels = 10000
o.autowrite = true
o.confirm = true -- ask instead of failing when quitting with unsaved changes
o.swapfile = false
o.sessionoptions = { "buffers", "curdir", "tabpages", "winsize", "folds" }

o.expandtab = true
o.shiftwidth = 2
o.tabstop = 2
o.shiftround = true
o.smartindent = true
o.linebreak = true
o.formatoptions = "jcroqlnt"
o.virtualedit = "block"
o.completeopt = "menu,menuone,noselect"

o.ignorecase = true
o.smartcase = true
o.inccommand = "nosplit" -- live preview of :s
o.grepprg = "rg --vimgrep"
o.grepformat = "%f:%l:%c:%m"

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

o.winborder = "rounded"
o.conceallevel = 2
o.list = true
o.fillchars = { foldopen = "▾", foldclose = "▸", fold = " ", eob = " ", diff = "╱" }
o.splitbelow = true
o.splitright = true
o.splitkeep = "screen"
o.laststatus = 3 -- one global statusline, not one per window
o.cmdheight = 0

pcall(function()
  -- messages go to the ephemeral toast window, not the cmdline: with cmdheight=0
  -- every cmdline message expands into the pager and needs ENTER to dismiss
  require("vim._core.ui2").enable({
    msg = {
      targets = "msg",
      msg = { timeout = 1500, height = 0.2 },
    },
  })
end)

-- dim the toast so it reads as a footnote, not an alert
vim.api.nvim_create_autocmd("FileType", {
  pattern = "msg",
  callback = function()
    vim.wo.winhighlight = "NormalFloat:Comment,FloatBorder:Comment"
    vim.wo.winblend = 20
  end,
})
o.showtabline = 1 -- tabline only when lua/statusline.lua says there's something to show
o.shortmess:append({ W = true, I = true, c = true, C = true, s = true })
o.report = 9999 -- no "N lines yanked/deleted" toast
o.timeoutlen = 300
o.updatetime = 200
o.jumpoptions = "view"
o.spelllang = { "en" }

o.foldlevel = 99
o.foldmethod = "expr"
o.foldexpr = "v:lua.vim.treesitter.foldexpr()"
o.foldtext = ""

o.mouse = ""

o.clipboard = vim.env.SSH_CONNECTION and "" or "unnamedplus"

o.exrc = true


vim.treesitter.language.register("html", { "html", "tmpl" })
vim.treesitter.language.register("templ", { "templ", "tmpl" })

vim.treesitter.language.register("tsx", { "typescriptreact" })
vim.treesitter.language.register("javascript", { "javascriptreact" })
vim.treesitter.language.register("bash", { "sh", "zsh", "env" })
vim.treesitter.language.register("json", { "jsonc" })
vim.treesitter.language.register("ini", { "dosini", "confini" })
vim.treesitter.language.register("git_config", { "gitconfig" })
vim.treesitter.language.register("ssh_config", { "sshconfig" })

vim.filetype.add({
  extension = { caddy = "caddy", bu = "yaml" },
  filename = {
    Caddyfile = "caddy",
    ["docker-compose.yml"] = "yaml.docker-compose",
    ["docker-compose.yaml"] = "yaml.docker-compose",
    ["compose.yml"] = "yaml.docker-compose",
    ["compose.yaml"] = "yaml.docker-compose",
  },
})


vim.o.guifont = "JetBrainsMono Nerd Font:h12"

if vim.g.neovide then
  vim.g.neovide_text_gamma = 0.8
  vim.g.neovide_text_contrast = 0.1
end

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


vim.diagnostic.config({
  severity_sort = true,
  underline = true,
  update_in_insert = false,
  virtual_text = { spacing = 4, source = "if_many" },
  signs = {
    text = {
      [vim.diagnostic.severity.ERROR] = "\u{f057} ",
      [vim.diagnostic.severity.WARN] = "\u{f071} ",
      [vim.diagnostic.severity.INFO] = "\u{f05a} ",
      [vim.diagnostic.severity.HINT] = "\u{f0eb} ",
    },
  },
  float = { source = "if_many" }, -- border comes from 'winborder'
})
