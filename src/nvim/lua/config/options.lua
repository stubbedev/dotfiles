-- This file is automatically loaded by plugins.core
vim.g.mapleader = " "
vim.g.maplocalleader = vim.g.mapleader

-- Enable LazyVim auto format
vim.g.autoformat = false

-- LazyVim's lualine spec calls trouble.statusline() for a document-symbols
-- component. That eagerly loads trouble.nvim at startup and registers a
-- CursorMoved handler that re-queries LSP document symbols on every cursor
-- move (~0.5ms/move, 68% of this config's total CursorMoved cost) -- for a
-- component our own lualine setup (plugins/lualine.lua) never renders.
vim.g.trouble_lualine = false

-- LazyVim's python extra defaults to `pyright`, but modules/nvim.nix installs
-- basedpyright. The result was that no python language server started at all:
-- the extra enabled pyright, whose binary isn't on PATH, and python buffers
-- got ruff alone -- lint and format, but no types, completion or go-to-def.
vim.g.lazyvim_python_lsp = "basedpyright"
vim.opt.mouse = ""

-- Load project-local .nvim.lua/.nvimrc/.exrc from nvim's launch dir for
-- per-project config (post-save hooks, etc.). Neovim prompts to :trust each
-- file before it runs, so only trust repos you control.
vim.o.exrc = true

-- LazyVim root dir detection
-- Each entry can be:
-- * the name of a detector function like `lsp` or `cwd`
-- * a pattern or array of patterns like `.git` or `lua`.
-- * a function with signature `function(buf) -> string|string[]`
-- Prioritize .git over lsp to prevent subdirectory flake.nix from changing root
vim.g.root_spec = { ".git", "lsp", "cwd" }
vim.treesitter.language.register("html", { "html", "tmpl" })
vim.treesitter.language.register("templ", { "templ", "tmpl" })

vim.filetype.add({
  extension = { caddy = "caddy" },
  filename = { Caddyfile = "caddy" },
})

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
-- modules/terminal.nix verbatim; catppuccin-nvim's own mapping
-- picks different shades for 0/6/7/8/15.
for i, color in ipairs({
  "#45475a", "#f38ba8", "#a6e3a1", "#f9e2af", -- black red green yellow
  "#89b4fa", "#f5c2e7", "#94e2d5", "#bac2de", -- blue magenta cyan white
  "#585b70", "#f38ba8", "#a6e3a1", "#f9e2af", -- bright black red green yellow
  "#89b4fa", "#f5c2e7", "#94e2d5", "#a6adc8", -- bright blue magenta cyan white
}) do
  vim.g["terminal_color_" .. (i - 1)] = color
end

-- Folding
vim.opt.foldlevel = 99
vim.opt.foldtext = "v:lua.require'lazyvim.util'.ui.foldtext()"

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
