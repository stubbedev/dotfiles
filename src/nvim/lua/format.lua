local M = {}

function M.format()
  local buf = vim.api.nvim_get_current_buf()
  local client = vim.bo[buf].filetype == "nix" and vim.lsp.get_clients({ bufnr = buf, name = "shell_lsp" })[1]
  if client then
    client:request_sync("workspace/executeCommand", {
      command = "shellLsp.fixAll",
      arguments = { vim.uri_from_bufnr(buf) },
    }, 2000, buf)
  end
  require("conform").format({ async = true, lsp_format = "fallback" })
end

function M.setup()
  local conform = require("conform")

  conform.setup({
    formatters_by_ft = {
      html = { "prettier" },
      xml = { "prettier" },
      markdown = { "prettier" },
      yaml = { "prettier" },
      vue = { "prettier" },
      php = { "pint" },
      caddy = { "caddy" },
      lua = { "stylua" },
      go = { "goimports", "gofumpt" },
      templ = { "templ" },
      python = { "ruff_organize_imports", "ruff_format" },
      sql = { "sqruff" },
    },

    formatters = {
      pint = {
        command = require("conform.util").find_executable({ "vendor/bin/pint" }, "pint"),
      },
      caddy = { command = "caddy", args = { "fmt", "-" }, stdin = true },
      sqruff = { command = "sqruff", args = { "fix", "-" }, stdin = true },
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
    markdown = { "markdownlint-cli2" },
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
