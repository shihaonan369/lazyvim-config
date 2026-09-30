-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here
local map = vim.keymap.set
for i = 1, 9 do
  map("n", "g" .. i, "<cmd>" .. i .. "tabnext<cr>", { desc = "Go to tab " .. i, silent = true })
end

map({ "i", "v" }, "jk", "<esc>", { desc = "esc", silent = true })
map({ "i", "v" }, "kj", "<esc>", { desc = "esc", silent = true })
map({ "t" }, "jk", [[<C-\><C-n>]], { desc = "esc", silent = true })
map({ "t" }, "kj", [[<C-\><C-n>]], { desc = "esc", silent = true })

-- 窗口高度/宽度 拉满 ↔ 还原（与 C-方向键 微调同族，Shift = 拉满）
local function toggle_max_height()
  if vim.w.max_height then
    vim.cmd(("resize %d"):format(vim.w.max_height))
    vim.w.max_height = nil
  else
    vim.w.max_height = vim.fn.winheight(0)
    vim.cmd("resize 9999")
  end
end

-- 宽度拉满保持 resize 9999 原语义（其余窗口压到最小，1:1:x）。但兄弟窗被
-- 挤到 winwidth（默认 20，布局重算的强制加宽底线）以下后，任何一次重算
-- （picker 关浮窗等）都会把它抬回 20、差额从本窗偷走（"最大化后第一次开
-- picker 缩 ~10%"）。修法：最大化存续期间把重算底线对齐挤压底线（临时
-- winwidth=winminwidth——不能写死 1，nvim 强制 winwidth ≥ winminwidth，
-- E592），还原/窗口消亡时扫描恢复原值——只作用于最大化期间，不动常态
-- （ADR 0004）。高度无同类问题：winheight 默认即 1。
local saved_winwidth
local function sync_winwidth()
  local maximized = false
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.w[w].max_width then
      maximized = true
      break
    end
  end
  if maximized then
    if not saved_winwidth then
      saved_winwidth = vim.o.winwidth
    end
    vim.o.winwidth = vim.o.winminwidth
  elseif saved_winwidth then
    vim.o.winwidth = saved_winwidth
    saved_winwidth = nil
  end
end

local function toggle_max_width()
  if vim.w.max_width then
    vim.cmd(("vertical resize %d"):format(vim.w.max_width))
    vim.w.max_width = nil
  else
    vim.w.max_width = vim.fn.winwidth(0)
    vim.cmd("vertical resize 9999")
  end
  sync_winwidth()
end

-- 最大化语义的再宣示：布局被开/关窗外力改写后（equalalways 均分、neo-tree
-- 开窗的 vsplit 舞步都会重排别人——<leader>e 关/开侧栏即中招），把"其余
-- 窗收回 winminwidth、winfixwidth 侧栏保自身宽、keep 豁免的新窗不动、
-- 最大化窗吃剩余"重演一遍。目标宽度精确计算，不用 resize 9999（会碾碎
-- 刚开的侧栏）。
local function reassert_maximized(keep)
  local wins, holders = {}, {}
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_is_valid(w) and vim.api.nvim_win_get_config(w).relative == "" then
      wins[#wins + 1] = w
      if vim.w[w].max_width then
        holders[#holders + 1] = w
      end
    end
  end
  if #holders > 0 then
    for _, w in ipairs(wins) do
      if w ~= keep and not vim.w[w].max_width and not vim.wo[w].winfixwidth then
        if vim.api.nvim_win_get_width(w) > vim.o.winminwidth then
          pcall(vim.api.nvim_win_set_width, w, vim.o.winminwidth)
        end
      end
    end
    for _, h in ipairs(holders) do
      local others = 0
      for _, w in ipairs(wins) do
        if w ~= h then
          others = others + vim.api.nvim_win_get_width(w)
        end
      end
      local target = vim.o.columns - (#wins - 1) - others
      if target > vim.api.nvim_win_get_width(h) then
        pcall(vim.api.nvim_win_set_width, h, target)
      end
    end
  end
  sync_winwidth()
end

-- 关窗：释放的份额归还最大化窗；最大化窗自身消亡则只收走临时 winwidth
vim.api.nvim_create_autocmd("WinClosed", {
  callback = function()
    vim.schedule(function()
      reassert_maximized(nil)
    end)
  end,
})
-- 开窗：只重宣示侧栏类（winfixwidth）新窗——普通 vsplit 是用户要地方，
-- 视为放弃最大化的信号；延迟等新窗把自己 reshape 完（neo-tree 先 vsplit
-- 后定宽）。WinNew 的 afile 为空，取当前窗（新建即当前；抓错会被
-- winfixwidth 守卫拒绝，失败安全）
vim.api.nvim_create_autocmd("WinNew", {
  callback = function()
    local new = vim.api.nvim_get_current_win()
    vim.defer_fn(function()
      if
        vim.api.nvim_win_is_valid(new)
        and vim.api.nvim_win_get_config(new).relative == ""
        and vim.wo[new].winfixwidth
      then
        reassert_maximized(new)
      end
    end, 150)
  end,
})

map("n", "<C-S-Up>", toggle_max_height, { desc = "Toggle Max Window Height", silent = true })
map("n", "<C-S-Right>", toggle_max_width, { desc = "Toggle Max Window Width", silent = true })

local next_terminal_count = 1
local my_terminals = {}

local function new_shell_terminal(shell)
  -- 清理已失效的终端
  local valid_terminals = {}
  for _, terminal in ipairs(my_terminals) do
    if terminal.buf and vim.api.nvim_buf_is_valid(terminal.buf) then
      table.insert(valid_terminals, terminal)
    end
  end
  my_terminals = valid_terminals

  -- 先显示所有已隐藏的终端，确保布局一致
  for _, terminal in ipairs(my_terminals) do
    if not terminal.win or not vim.api.nvim_win_is_valid(terminal.win) then
      local enter = terminal.opts.enter
      terminal.opts.enter = false
      terminal:show()
      terminal.opts.enter = enter
    end
  end

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

for i = 1, 4 do
  map("n", "<leader>z" .. i, function()
    for _ = 1, i do
      new_shell_terminal("zsh")
    end
  end, { desc = "New " .. i .. " zsh Terminals", silent = true })
end
