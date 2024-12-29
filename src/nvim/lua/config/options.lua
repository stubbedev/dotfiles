-- This file is automatically loaded by plugins.core
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- Enable LazyVim auto format
vim.g.autoformat = false
vim.opt.mouse = ""

-- LazyVim root dir detection
-- Each entry can be:
-- * the name of a detector function like `lsp` or `cwd`
-- * a pattern or array of patterns like `.git` or `lua`.
-- * a function with signature `function(buf) -> string|string[]`
vim.g.root_spec = { "lsp", { ".git", "lua" }, "cwd" }
vim.treesitter.language.register("html", { "html", "vue", "tmpl" })
vim.treesitter.language.register("templ", { "templ", "tmpl" })
vim.treesitter.language.register("coffeescript", { "coffee" })

-- Folding
vim.opt.foldlevel = 99
vim.opt.foldtext = "v:lua.require'lazyvim.util'.ui.foldtext()"

-- Fix PHP default lsp
vim.g.lazyvim_php_lsp = "intelephense"
