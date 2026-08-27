-- Sourced by mail-pager. conceallevel=2 hides link destinations so the body
-- reads as prose, and concealcursor keeps the cursor line hidden too --
-- unconcealing it would re-expand the markup and shove the rest of the line
-- sideways. The destination is shown in a float instead: an overlay layer, so
-- nothing in the rendered message moves.
--
-- Injections must be followed explicitly: without ignore_injections=false the
-- node chain stops at `inline` (markdown), never reaching the markdown_inline
-- nodes that actually carry the URL.
local function url_at_cursor()
  local ok, node = pcall(vim.treesitter.get_node, { ignore_injections = false })
  if not ok or not node then
    return nil
  end
  while node do
    local kind = node:type()
    if kind == "uri_autolink" then
      -- <https://example.com> -- strip the angle brackets the syntax requires.
      return vim.treesitter.get_node_text(node, 0):match("^<(.*)>$")
    elseif kind == "inline_link" or kind == "image" then
      for child in node:iter_children() do
        if child:type() == "link_destination" then
          return vim.treesitter.get_node_text(child, 0)
        end
      end
    end
    node = node:parent()
  end
  return nil
end

-- open_floating_preview closes itself on the next CursorMoved and reuses its
-- own window, so moving between two links swaps the contents rather than
-- stacking floats.
vim.api.nvim_create_autocmd("CursorMoved", {
  buffer = 0,
  callback = function()
    local url = url_at_cursor()
    if url then
      vim.lsp.util.open_floating_preview({ url }, "", {
        focusable = false,
        border = "rounded",
      })
    end
  end,
})
