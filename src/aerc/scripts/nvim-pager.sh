#!/usr/bin/env bash
# Aerc viewer pager: write the (already-filtered) message body to a temp
# file with a .md suffix and open it in nvim read-only.
#   - Markdown filetype gives syntax highlighting via the user's nvim setup.
#   - render-markdown.nvim is disabled for this buffer so vim's built-in
#     conceal works: cursor on a link line reveals the [text](url) form,
#     cursor elsewhere collapses to just `text`.
#   - LSP diagnostics are silenced so prose-linter warnings don't pollute
#     the read-only viewer.
#   - The companion .lua script tags every markdown link / bare URL with
#     an extmark url= attribute, which the nvim TUI translates into OSC 8
#     hyperlinks. Alacritty's URL hint already accepts OSC 8 via
#     hyperlinks=true, and unlike its per-line regex those span wrapped
#     lines — so click-to-open works even when the visible link text
#     breaks across two screen rows.
set -euo pipefail

tmp=$(mktemp --suffix=.md /tmp/aerc-XXXXXX)
trap 'rm -f "$tmp"' EXIT

cat > "$tmp"

exec nvim -R \
  --cmd 'set noswapfile' \
  -c 'silent! RenderMarkdown disable' \
  -c 'lua vim.diagnostic.enable(false)' \
  -c 'setlocal conceallevel=2 concealcursor= nomodifiable' \
  -S "$HOME/.config/aerc/scripts/nvim-pager.lua" \
  "$tmp"
