local M = {}

local dials_by_ft = {
  css = "css",
  scss = "css",
  sass = "css",
  vue = "vue",
  javascript = "typescript",
  javascriptreact = "typescript",
  typescript = "typescript",
  typescriptreact = "typescript",
  json = "json",
  lua = "lua",
  markdown = "markdown",
  python = "python",
}

local function dial(increment, g)
  local mode = vim.fn.mode(true)
  local visual = mode == "v" or mode == "V" or mode == "\22"
  local func = (increment and "inc" or "dec") .. (g and "_g" or "_") .. (visual and "visual" or "normal")
  return require("dial.map")[func](dials_by_ft[vim.bo.filetype] or "default")
end

function M.setup()
  local augend = require("dial.augend")

  local groups = {
    default = {
      augend.integer.alias.decimal,
      augend.integer.alias.decimal_int,
      augend.integer.alias.hex,
      augend.date.alias["%Y/%m/%d"],
      augend.date.alias["%Y-%m-%d"],
      augend.constant.alias.en_weekday,
      augend.constant.alias.en_weekday_full,
      augend.constant.alias.bool,
      augend.constant.alias.Bool,
      augend.constant.new({ elements = { "&&", "||" }, word = false, cyclic = true }),
      augend.constant.new({
        elements = {
          "January",
          "February",
          "March",
          "April",
          "May",
          "June",
          "July",
          "August",
          "September",
          "October",
          "November",
          "December",
        },
        word = true,
        cyclic = true,
      }),
      augend.constant.new({
        elements = {
          "first",
          "second",
          "third",
          "fourth",
          "fifth",
          "sixth",
          "seventh",
          "eighth",
          "ninth",
          "tenth",
        },
        word = false,
        cyclic = true,
      }),
    },
    css = {
      augend.hexcolor.new({ case = "lower" }),
      augend.hexcolor.new({ case = "upper" }),
    },
    vue = {
      augend.constant.new({ elements = { "let", "const" } }),
      augend.hexcolor.new({ case = "lower" }),
      augend.hexcolor.new({ case = "upper" }),
    },
    typescript = {
      augend.constant.new({ elements = { "let", "const" } }),
    },
    markdown = {
      augend.constant.new({ elements = { "[ ]", "[x]" }, word = false, cyclic = true }),
      augend.misc.alias.markdown_header,
    },
    json = {
      augend.semver.alias.semver,
    },
    lua = {
      augend.constant.new({ elements = { "and", "or" }, word = true, cyclic = true }),
    },
    python = {
      augend.constant.new({ elements = { "and", "or" }, word = true, cyclic = true }),
    },
  }

  for name, group in pairs(groups) do
    if name ~= "default" then
      vim.list_extend(group, groups.default)
    end
  end

  require("dial.config").augends:register_group(groups)

  local map = vim.keymap.set
  map({ "n", "x" }, "<C-a>", function()
    return dial(true)
  end, { expr = true, desc = "Increment" })
  map({ "n", "x" }, "<C-x>", function()
    return dial(false)
  end, { expr = true, desc = "Decrement" })
  map({ "n", "x" }, "g<C-a>", function()
    return dial(true, true)
  end, { expr = true, desc = "Increment (g)" })
  map({ "n", "x" }, "g<C-x>", function()
    return dial(false, true)
  end, { expr = true, desc = "Decrement (g)" })
end

return M
