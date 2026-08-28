-- AI completion, replacing LazyVim's `ai.copilot` extra (dropped from
-- config/lazy.lua). copilot.lua drives a Node language server that idles at
-- ~650M *private* RSS per nvim session — three open sessions cost ~2G.
-- Codeium's server is a single prebuilt native binary, installed from
-- nixpkgs as `codeium` in modules/nvim.nix.
--
-- Requires a Windsurf/Codeium account: `:Codeium Auth` on first use.
return {
  {
    "Exafunction/windsurf.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    event = "InsertEnter",
    opts = {
      -- Pin the server to the nixpkgs binary. Without this the plugin
      -- downloads its own copy into ~/.cache/codeium/bin at runtime. An
      -- empty exepath (binary missing from runtimePkgs) fails loudly rather
      -- than silently falling back to that download, which is what we want.
      tools = { language_server = vim.fn.exepath("codeium_language_server") },

      -- Completions come from the blink source registered in blink.lua.
      -- enable_cmp_source is nvim-cmp's; virtual_text stays off (its default)
      -- so ghost text doesn't double up with the completion menu.
      enable_cmp_source = false,

      -- Per-workspace background services we don't use — the indexer walks
      -- up to 5000 files by default, which is exactly the kind of resident
      -- cost this swap exists to avoid.
      enable_chat = false,
      enable_index_service = false,
    },
  },
}
