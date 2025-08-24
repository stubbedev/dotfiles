-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here
local map = LazyVim.safe_keymap_set

map("n", "<leader>ll", "<cmd>Lazy<cr>", { desc = "Lazy" })
map("n", "<leader>le", "<cmd>LazyExtras<cr>", { desc = "LazyExtras" })
map("n", "<S-h>", "<cmd>bprevious<cr>", { desc = "Prev Buffer" })
map("n", "<S-l>", "<cmd>bnext<cr>", { desc = "Next Buffer" })
map("n", "[b", "<cmd>bprevious<cr>", { desc = "Prev Buffer" })
map("n", "]b", "<cmd>bnext<cr>", { desc = "Next Buffer" })
-- map("n", "<C-1>", "<cmd>LuaLineBuffersJump 0", { desc = "1st Buffer" })
-- map("n", "<C-2>", "<cmd>LuaLineBuffersJump 1", { desc = "2nd Buffer" })
-- map("n", "<C-3>", "<cmd>LuaLineBuffersJump 2", { desc = "3rd Buffer" })
-- map("n", "<C-4>", "<cmd>LuaLineBuffersJump 3", { desc = "4th Buffer" })
-- map("n", "<C-5>", "<cmd>LuaLineBuffersJump 4", { desc = "5th Buffer" })
-- map("n", "<C-6>", "<cmd>LuaLineBuffersJump 5", { desc = "6th Buffer" })
-- map("n", "<C-7>", "<cmd>LuaLineBuffersJump 6", { desc = "7th Buffer" })
-- map("n", "<C-8>", "<cmd>LuaLineBuffersJump 7", { desc = "8th Buffer" })
-- map("n", "<C-9>", "<cmd>LuaLineBuffersJump 8", { desc = "9th Buffer" })
-- map("n", "<C-0>", "<cmd>LuaLineBuffersJump 9", { desc = "10th Buffer" })
