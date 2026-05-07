#!/usr/bin/env bash
# Aerc viewer pager: write the (already-filtered) message body to a temp
# file with a .md suffix and open it in nvim read-only.
#   - Markdown filetype gives syntax highlighting via the user's nvim setup.
#   - LSP diagnostics are silenced so prose-linter warnings don't pollute
#     the read-only viewer.
#   - The companion .lua script rewrites every [text](url) to just `text`
#     and attaches the URL via an extmark `url=` attribute, which the nvim
#     TUI emits as an OSC 8 hyperlink. Alacritty's URL hint already
#     recognises OSC 8 (hyperlinks = true), so click-to-open still works.
#     Rewriting (rather than concealing) is required because vim computes
#     wrap points from the raw buffer, not the displayed width — both
#     built-in conceal and render-markdown.nvim's extmark conceal would
#     leave phantom blank rows where the URL used to be. The lua script
#     also flips the buffer to nomodifiable once the rewrite is done.
set -euo pipefail

tmp=$(mktemp --suffix=.md /tmp/aerc-XXXXXX)
trap 'rm -f "$tmp"' EXIT

cat > "$tmp"

exec nvim -R \
  --cmd 'set noswapfile' \
  -c 'lua vim.diagnostic.enable(false)' \
  -S "$HOME/.config/aerc/scripts/nvim-pager.lua" \
  "$tmp"
