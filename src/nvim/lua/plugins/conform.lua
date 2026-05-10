return {
  "stevearc/conform.nvim",
  opts_extend = { "formatters_by_ft" },
  opts = function(_, opts)
    opts.formatters_by_ft = opts.formatters_by_ft or {}
    -- html/xml/markdown/vue: prettier with ~/.prettierrc.json
    opts.formatters_by_ft.html = { "prettier" }
    opts.formatters_by_ft.xml = { "prettier" }
    opts.formatters_by_ft.markdown = { "prettier" }
    opts.formatters_by_ft.vue = { "prettier" }
    -- js/ts/json/css/scss: handled by oxfmt LSP
    opts.formatters_by_ft.php = { "pint" }
    opts.formatters_by_ft.caddy = { "caddy" }
    -- nix: auto-fix lints, drop dead code, then format. Order matters.
    opts.formatters_by_ft.nix = { "statix", "deadnix", "nixfmt" }

    opts.formatters = opts.formatters or {}
    opts.formatters.caddy = { command = "caddy", args = { "fmt", "-" }, stdin = true }
    opts.formatters.statix = {
      command = "statix",
      args = { "fix", "--stdin" },
      stdin = true,
    }
    opts.formatters.deadnix = {
      -- deadnix has no stdin mode; conform.nvim writes the buffer to a
      -- tmpfile when stdin=false, passes its path as $FILENAME, runs
      -- deadnix --edit on it, then reads the result back into the buffer.
      command = "deadnix",
      args = { "--edit", "--quiet", "$FILENAME" },
      stdin = false,
    }

    return opts
  end,
}
