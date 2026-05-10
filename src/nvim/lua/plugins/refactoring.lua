-- LazyVim's `extras/editor/refactoring` enables ThePrimeagen/refactoring.nvim
-- but does not declare the `lewis6991/async.nvim` dependency. refactoring.nvim
-- does `require("async")` at config time and crashes with "module 'async' not
-- found" without it.
return {
  { "lewis6991/async.nvim", lazy = true },
  {
    "ThePrimeagen/refactoring.nvim",
    dependencies = { "lewis6991/async.nvim" },
  },
}
