-- Add deadnix (unused let-bindings/args) on top of statix that LazyVim's
-- lang.nix extra already configures.
return {
  {
    "mfussenegger/nvim-lint",
    optional = true,
    opts = {
      linters_by_ft = {
        nix = { "statix", "deadnix" },
      },
    },
  },
}
