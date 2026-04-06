-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here
local map = vim.keymap.set
map({ "i", "v" }, "jk", "<esc>", { desc = "esc", silent = true })
map({ "i", "v" }, "kj", "<esc>", { desc = "esc", silent = true })
map({ "t" }, "jk", [[<C-\><C-n>]], { desc = "esc", silent = true })
map({ "t" }, "kj", [[<C-\><C-n>]], { desc = "esc", silent = true })
map({ "n" }, "<C-M-j>", "<C-w>-", { desc = "Decrease Window Height", silent = true })
map({ "n" }, "<C-M-k>", "<C-w>+", { desc = "Increase Window Height", silent = true })
map({ "n" }, "<C-M-h>", "<C-w><", { desc = "Decrease Window Width", silent = true })
map({ "n" }, "<C-M-l>", "<C-w>>", { desc = "Increase Window Width", silent = true })

local next_terminal_count = 1

local function new_shell_terminal(shell)
  Snacks.terminal({ shell }, {
    cwd = LazyVim.root(),
    count = next_terminal_count,
    win = { position = "bottom" },
  })
  next_terminal_count = next_terminal_count + 1
end

local function toggle_all_terminals()
  local terminals = Snacks.terminal.list()
  if #terminals == 0 then
    new_shell_terminal(vim.o.shell)
    return
  end

  local has_visible = vim.iter(terminals):any(function(terminal)
    return terminal:valid()
  end)

  for _, terminal in ipairs(terminals) do
    if has_visible then
      terminal:hide()
    else
      local enter = terminal.opts.enter
      terminal.opts.enter = false
      terminal:show()
      terminal.opts.enter = enter
    end
  end
end

local function toggle_all_terminals_from_terminal()
  vim.cmd.stopinsert()
  vim.schedule(toggle_all_terminals)
end

vim.api.nvim_create_autocmd("FileType", {
  pattern = "snacks_terminal",
  callback = function(event)
    for _, lhs in ipairs({ "<C-/>", "<C-_>" }) do
      pcall(vim.keymap.del, "n", lhs, { buffer = event.buf })
      pcall(vim.keymap.del, "t", lhs, { buffer = event.buf })
    end
  end,
})

for _, lhs in ipairs({ "<C-/>", "<C-_>" }) do
  pcall(vim.keymap.del, "n", lhs)
  pcall(vim.keymap.del, "t", lhs)
  map("n", lhs, toggle_all_terminals, { desc = "Toggle All Terminals", silent = true })
  map("t", lhs, toggle_all_terminals_from_terminal, { desc = "Toggle All Terminals", silent = true })
end

map("n", "<leader>tz", function()
  new_shell_terminal("zsh")
end, { desc = "New zsh Terminal", silent = true })

map("n", "<leader>tb", function()
  new_shell_terminal("bash")
end, { desc = "New bash Terminal", silent = true })

map("n", "<leader>tt", function()
  new_shell_terminal(vim.o.shell)
end, { desc = "New Terminal", silent = true })
