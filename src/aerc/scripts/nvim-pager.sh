#!/usr/bin/env bash
# Aerc viewer pager: write the (already-filtered) message body to a temp
# file with a .md suffix and open it in nvim read-only.
#   - Markdown filetype gives syntax highlighting via the user's nvim setup.
#   - render-markdown.nvim is disabled for this buffer because we want
#     vim's built-in conceal: cursor on a link line reveals the URL,
#     cursor elsewhere keeps the [text] form.
#   - LSP diagnostics are silenced so prose-linter warnings don't pollute
#     the read-only viewer.
set -euo pipefail

tmp=$(mktemp --suffix=.md /tmp/aerc-XXXXXX)
trap 'rm -f "$tmp"' EXIT

cat > "$tmp"

exec nvim -R \
  --cmd 'set noswapfile' \
  -c 'silent! RenderMarkdown disable' \
  -c 'lua vim.diagnostic.enable(false)' \
  -c 'setlocal conceallevel=2 concealcursor= nomodifiable' \
  "$tmp"
