
local M = {}

function M.setup()
  local conform = require("conform")

  conform.setup({
    formatters_by_ft = {
      html = { "prettier" },
      xml = { "prettier" },
      markdown = { "prettier" },
      vue = { "prettier" },
      php = { "pint" },
      caddy = { "caddy" },
      sh = { "shfmt" },
      bash = { "shfmt" },
      zsh = { "shfmt" },
      lua = { "stylua" },
      go = { "goimports", "gofumpt" },
      python = { "ruff_organize_imports", "ruff_format" },
      sql = { "sqruff" },
      nix = { "statix", "deadnix", "nixfmt" },
    },

    formatters = {
      pint = {
        command = require("conform.util").find_executable({ "vendor/bin/pint" }, "pint"),
      },
      caddy = { command = "caddy", args = { "fmt", "-" }, stdin = true },
      sqruff = { command = "sqruff", args = { "fix", "-" }, stdin = true },
      statix = { command = "statix", args = { "fix", "--stdin" }, stdin = true },
      deadnix = {
        command = "deadnix",
        args = { "--edit", "--quiet", "$FILENAME" },
        stdin = false,
      },
    },
  })

  vim.api.nvim_create_autocmd("BufWritePost", {
    group = vim.api.nvim_create_augroup("php_pint_on_save", { clear = true }),
    pattern = "*.php",
    callback = function(args)
      local buf = args.buf
      local dir = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":h")
      if not vim.fs.find("vendor/bin/pint", { upward = true, path = dir })[1] then
        return
      end
      conform.format({
        bufnr = buf,
        formatters = { "pint" },
        lsp_format = "never",
        async = true,
        timeout_ms = 10000,
      }, function(err)
        if err or not vim.api.nvim_buf_is_valid(buf) or not vim.bo[buf].modified then
          return
        end
        vim.api.nvim_buf_call(buf, function()
          vim.cmd("noautocmd silent write")
        end)
      end)
    end,
  })

  local lint = require("lint")

  lint.linters_by_ft = {
    nix = { "statix", "deadnix" },
    markdown = { "markdownlint-cli2" },
    dockerfile = { "hadolint" },
  }

  local timer = assert(vim.uv.new_timer())
  local function lint_debounced()
    if not lint.linters_by_ft[vim.bo.filetype] then
      return
    end
    timer:stop()
    timer:start(
      300,
      0,
      vim.schedule_wrap(function()
        lint.try_lint()
      end)
    )
  end

  vim.api.nvim_create_autocmd({ "BufWritePost", "BufReadPost", "InsertLeave", "TextChanged" }, {
    group = vim.api.nvim_create_augroup("nvim_lint", { clear = true }),
    callback = lint_debounced,
  })
end

return M
