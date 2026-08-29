-- Neovim config.
--
-- Three layers, each owning exactly one thing:
--   modules/nvim.nix  every binary (language servers, linters, formatters) and
--                     the treesitter parsers, pinned by flake.lock
--   lua/plugins.lua   the editor plugins, via nvim 0.12's built-in vim.pack
--   lua/*.lua         plain config -- no framework, no spec DSL
--
-- Load order matters: options sets the leader before any mapping is made,
-- plugins must be on the runtimepath before anything requires them, and lsp
-- asks blink.cmp for its completion capabilities. lua/format.lua is not here:
-- conform and nvim-lint are deferred, so plugins.lua calls its setup() once the
-- UI is up.

require("options")
require("plugins")
require("lsp")
require("statusline")
require("keymaps")
require("autocmds")
