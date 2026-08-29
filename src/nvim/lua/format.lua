-- Formatting and linting. Both are thin drivers over binaries that come from
-- nix (modules/nvim.nix) -- conform runs formatters, nvim-lint runs the
-- linters that aren't already language servers.
--
-- conform and nvim-lint are deferred plugins, so this module exposes a setup()
-- that lua/plugins.lua calls from its post-UI hook rather than doing the work
-- at require time.

local M = {}

function M.setup()
  local conform = require("conform")

  conform.setup({
    formatters_by_ft = {
      -- js/ts/json/css/scss are formatted by the oxfmt language server, not here.
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
      -- nix: auto-fix lints, drop dead code, then format. Order matters.
      nix = { "statix", "deadnix", "nixfmt" },
    },

    formatters = {
      -- Resolve the project's ./vendor/bin/pint (searched upward from the
      -- file), falling back to a global `pint` if one is ever on PATH. Each
      -- project formats with its own pint binary and its own pint.json.
      pint = {
        command = require("conform.util").find_executable({ "vendor/bin/pint" }, "pint"),
      },
      caddy = { command = "caddy", args = { "fmt", "-" }, stdin = true },
      sqruff = { command = "sqruff", args = { "fix", "-" }, stdin = true },
      statix = { command = "statix", args = { "fix", "--stdin" }, stdin = true },
      deadnix = {
        -- deadnix has no stdin mode; conform writes the buffer to a tmpfile
        -- when stdin=false, passes its path as $FILENAME, runs deadnix --edit
        -- on it, then reads the result back into the buffer.
        command = "deadnix",
        args = { "--edit", "--quiet", "$FILENAME" },
        stdin = false,
      },
    },
  })

  -- Format-on-save is off globally -- reformatting a file someone else owns
  -- turns a one-line change into a hundred-line diff. `<leader>cf` formats on
  -- demand (lua/keymaps.lua); PHP is the one exception below.
  --
  -- PHP: format with the project's Pint on save, but only where the project
  -- actually ships vendor/bin/pint -- per-project by detection, no per-repo
  -- config, and it resolves upward so git worktrees work too.
  --
  -- Async, on BufWritePost rather than BufWritePre: pint is a PHP process
  -- running PHP-CS-Fixer and takes ~1.4s on a 2800-line file, so formatting
  -- inline made every :w block for that long. conform applies the result only
  -- if the buffer is untouched since the format started, so typing during
  -- those 1.4s cancels the rewrite rather than clobbering the edit.
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
        -- Nothing to write back if pint failed or made no change.
        if err or not vim.api.nvim_buf_is_valid(buf) or not vim.bo[buf].modified then
          return
        end
        vim.api.nvim_buf_call(buf, function()
          vim.cmd("noautocmd silent write")
        end)
      end)
    end,
  })

  -- Linting -----------------------------------------------------------------
  --
  -- Only for languages whose linter isn't already a language server.
  -- Everything JS/TS is oxlint (an LSP), PHP is phpantom's bundled
  -- mago/PHPStan, shell is bashls' shellcheck integration.
  local lint = require("lint")

  lint.linters_by_ft = {
    nix = { "statix", "deadnix" },
    markdown = { "markdownlint-cli2" },
    dockerfile = { "hadolint" },
  }

  -- try_lint() spawns a process per linter, so firing it straight off
  -- InsertLeave means a statix and a deadnix per exit from insert mode. Debounce
  -- to one run per quiet 300ms, and only for buffers that actually have a
  -- linter -- the timer is otherwise pure overhead on every other filetype.
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
