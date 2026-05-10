-- LazyVim's `extras/editor/refactoring` enables ThePrimeagen/refactoring.nvim
-- but doesn't declare its `lewis6991/async.nvim` dependency. Recent
-- refactoring.nvim does `require("async")` at config time and crashes
-- with "module 'async' not found" if it isn't installed.
return {
  { "lewis6991/async.nvim", lazy = true },
  {
    "ThePrimeagen/refactoring.nvim",
    dependencies = { "lewis6991/async.nvim" },
  },
}
