-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here
local map = vim.keymap.set
map({ "i", "v" }, "jk", "<esc>", { desc = "esc", silent = true })
map({ "i", "v" }, "kj", "<esc>", { desc = "esc", silent = true })
map({ "t" }, "jk", [[<C-\><C-n>]], { desc = "esc", silent = true })
map({ "t" }, "kj", [[<C-\><C-n>]], { desc = "esc", silent = true })
map({ "n" }, "<C-S-j>", "<C-w>-", { desc = "Decrease Window Height", silent = true })
map({ "n" }, "<C-S-k>", "<C-w>+", { desc = "Increase Window Height", silent = true })
map({ "n" }, "<C-S-h>", "<C-w><", { desc = "Decrease Window Width", silent = true })
map({ "n" }, "<C-S-l>", "<C-w>>", { desc = "Increase Window Width", silent = true })
