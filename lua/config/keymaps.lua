-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here
local map = vim.keymap.set
map({ "i", "v" }, "jk", "<esc>", { desc = "esc", silent = true })
map({ "i", "v" }, "kj", "<esc>", { desc = "esc", silent = true })
map({ "t" }, "jk", [[<C-\><C-n>]], { desc = "esc", silent = true })
map({ "t" }, "kj", [[<C-\><C-n>]], { desc = "esc", silent = true })

local next_terminal_count = 1
local my_terminals = {}

local function new_shell_terminal(shell)
  local terminal = Snacks.terminal({ shell }, {
    cwd = LazyVim.root(),
    count = next_terminal_count,
    win = { position = "bottom" },
  })
  next_terminal_count = next_terminal_count + 1
  table.insert(my_terminals, terminal)
end

local function toggle_all_terminals()
  if #my_terminals == 0 then
    new_shell_terminal(vim.o.shell)
    return
  end

  -- 清理已失效的终端（通过检查缓冲区是否有效）
  local valid_terminals = {}
  for _, terminal in ipairs(my_terminals) do
    if terminal.buf and vim.api.nvim_buf_is_valid(terminal.buf) then
      table.insert(valid_terminals, terminal)
    end
  end
  my_terminals = valid_terminals

  if #my_terminals == 0 then
    new_shell_terminal(vim.o.shell)
    return
  end

  -- 检查是否有可见的终端
  local has_visible = vim.iter(my_terminals):any(function(terminal)
    return terminal.win and vim.api.nvim_win_is_valid(terminal.win)
  end)

  for _, terminal in ipairs(my_terminals) do
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

map("n", "<leader>zz", function()
  new_shell_terminal("zsh")
end, { desc = "New zsh Terminal", silent = true })
