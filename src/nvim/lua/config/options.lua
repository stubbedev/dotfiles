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
-- Prioritize .git over lsp to prevent subdirectory flake.nix from changing root
vim.g.root_spec = { ".git", "lsp", "cwd" }
vim.treesitter.language.register("html", { "html", "vue", "tmpl" })
vim.treesitter.language.register("templ", { "templ", "tmpl" })

-- Folding
vim.opt.foldlevel = 99
vim.opt.foldtext = "v:lua.require'lazyvim.util'.ui.foldtext()"

-- Fix PHP default lsp
vim.g.lazyvim_php_lsp = "intelephense"

vim.lsp.handlers["textDocument/hover"] = function(_, result, ctx, config)
  config = config or {}
  config.focus_id = ctx.method
  if not (result and result.contents) then
    return
  end
  local markdown_lines = vim.lsp.util.convert_input_to_markdown_lines(result.contents)
  local markdown_lines_string = table.concat(markdown_lines, "\n")
  markdown_lines = vim.split(markdown_lines_string, "\r\n|\r|\n", { trimempty = true })
  if vim.tbl_isempty(markdown_lines) then
    return
  end
  return vim.lsp.util.open_floating_preview(markdown_lines, "markdown", config)
end
