-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here
local map = vim.keymap.set
map({ "i", "v" }, "jk", "<esc>", { desc = "esc", silent = true })
map({ "i", "v" }, "kj", "<esc>", { desc = "esc", silent = true })
