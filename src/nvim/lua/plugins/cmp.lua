return {
  "xzbdmw/colorful-menu.nvim",
  dependencies = {
    "saghen/blink.cmp",
  },
  config = function()
    require("blink.cmp").setup({
      completion = {
        menu = {
          draw = {
            components = {
              label = {
                width = { fill = true, max = 60 },
                text = function(ctx)
                  local highlights_info = require("colorful-menu").highlights(ctx.item, vim.bo.filetype)
                  if highlights_info ~= nil then
                    return highlights_info.text
                  else
                    return ctx.label
                  end
                end,
                highlight = function(ctx)
                  local highlights_info = require("colorful-menu").highlights(ctx.item, vim.bo.filetype)
                  local highlights = {}
                  if highlights_info ~= nil then
                    for _, info in ipairs(highlights_info.highlights) do
                      table.insert(highlights, {
                        info.range[1],
                        info.range[2],
                        group = ctx.deprecated and "BlinkCmpLabelDeprecated" or info[1],
                      })
                    end
                  end
                  for _, idx in ipairs(ctx.label_matched_indices) do
                    table.insert(highlights, { idx, idx + 1, group = "BlinkCmpLabelMatch" })
                  end
                  return highlights
                end,
              },
            },
          },
        },
      },
    })
  end,
}
