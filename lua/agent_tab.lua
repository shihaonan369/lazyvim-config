-- agent_tab: agent tab 视口（docs/adr/0005）
-- 左 = neo-tree agent_tree 源（列表/切换/新建/删除），右 = session 显示窗。
-- 与 Agent pane 长期并存（编辑为主用 pane，agent 为主用 tab），不是过渡形态。
-- 架构：单一全局 current、所有显示窗同步——本模块经 agent_sessions 的
-- alt_viewport 注册口接入（active/show），后台联动走既有 User
-- AgentSessionsChanged 事件（emit 管线，零轮询，与 docs/adr/0003 同源）。
local agent = require("agent_sessions")

local M = {}

local TREE_WIDTH = 40
local WELCOME_NAME = "agent-tab://welcome"

local set_up = false

local function is_agent_tab(tab)
  return vim.t[tab].agent_tab == true
end

-- 唯一的 agent tab（幂等判据；多个 marker 属异常，取第一个）
function M.tab()
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    if is_agent_tab(tab) then return tab end
  end
end

-- agent_sessions.display 的路由判据：当前 tab 是否 agent tab
function M.active()
  return is_agent_tab(vim.api.nvim_get_current_tabpage())
end

-- 显示窗（tab var 记 winid；失效=被用户关闭）
local function display_win(tab)
  local win = vim.t[tab].agent_display
  if win
    and vim.api.nvim_win_is_valid(win)
    and vim.api.nvim_win_get_tabpage(win) == tab
  then
    return win
  end
end

local function tree_win(tab)
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
    if vim.w[w].agent_tree == true then return w end
  end
end

-- 欢迎页：空态显示窗的合法内容（领地守卫唯一豁免，bufvar 标记，ADR 0005）
local function welcome_buf()
  local buf = vim.fn.bufnr("^" .. WELCOME_NAME .. "$")
  if buf == -1 then
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, WELCOME_NAME)
    vim.b[buf].agent_tab_welcome = true
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "hide"
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "  󰚩 Agent tab",
      "",
      "  没有 session。左侧树按 a（或 <leader>an）新建。",
      "  树内：<CR> 切换 · a 新建 · d 删除",
      "  <leader>at 再次进入本 tab 为 no-op，gt/gN 切走即可",
    })
    vim.bo[buf].modifiable = false
  end
  return buf
end

local function open_tree()
  -- neo-tree 未装/未加载的场合（headless --clean 测试）静默降级：左窗保持占位
  pcall(function()
    require("neo-tree.command").execute({ source = "agent_tree", position = "current", action = "show" })
  end)
end

-- 在 base 右侧开出显示窗（显式显示路径用；同步路径不重建，尊重用户关窗）
local function build_display(tab, base)
  local win
  vim.api.nvim_win_call(base, function()
    vim.cmd("rightbelow vsplit")
    win = vim.api.nvim_get_current_win()
  end)
  vim.w[win].agent_pane = true -- 领地身份：ADR 0002 守卫自动覆盖（ADR 0005）
  vim.t[tab].agent_display = win
  return win
end

local function ensure_tree(tab)
  if tree_win(tab) then return end
  local base = display_win(tab) or vim.api.nvim_tabpage_list_wins(tab)[1]
  local win
  vim.api.nvim_win_call(base, function()
    vim.cmd("leftabove vsplit") -- 树恒在左（ADR 0005 布局）
    win = vim.api.nvim_get_current_win()
  end)
  if win then
    vim.w[win].agent_tree = true
    vim.api.nvim_win_set_width(win, TREE_WIDTH)
    vim.api.nvim_set_current_win(win)
    open_tree()
  end
end

-- 显示窗应持有的 buffer：session buf，无 current 落欢迎页
local function set_display_buf(win, id)
  local buf = (id and agent.buf_of(id)) or welcome_buf()
  if vim.api.nvim_win_get_buf(win) ~= buf then
    vim.api.nvim_win_set_buf(win, buf)
  end
  return buf
end

-- 焦点落显示窗；terminal 才 startinsert（欢迎页不进 insert）
local function focus_display(win)
  vim.api.nvim_set_current_win(win)
  if vim.bo[vim.api.nvim_win_get_buf(win)].buftype == "terminal" then
    vim.cmd("startinsert")
  end
end

-- alt_viewport.show：右窗换 buffer（session buf 或欢迎页），可选焦点
function M.show(id, focus)
  local tab = M.tab()
  if not tab then return end
  local win = display_win(tab) or build_display(tab, vim.api.nvim_tabpage_list_wins(tab)[1])
  set_display_buf(win, id)
  if focus then focus_display(win) end
end

-- 显示窗跟随 current；全灭转欢迎页。不重建被关的窗、不夺焦点。
-- TermClose 删死 buffer 前同步调用（事件管线是 schedule 延迟的，赶不上
-- 删除时刻——bd! 会连带关掉还显示着死 buffer 的窗，ADR 0005）
local function sync()
  local tab = M.tab()
  if not tab then return end
  local win = display_win(tab)
  if not win then return end
  set_display_buf(win, agent.current_id())
end

-- User AgentSessionsChanged：同步显示窗 + 刷新树（零轮询，ADR 0003 同源）
local function on_changed()
  sync()
  pcall(function() require("neo-tree.sources.manager").refresh("agent_tree") end)
end

-- <leader>at：agent tab 内撤映射（no-op 且 which-key 不列不可用键），离开恢复
local function map_at()
  vim.keymap.set("n", "<leader>at", function() M.toggle() end, { desc = "Agent tab", silent = true })
end

function M.toggle()
  local tab = M.tab()
  if tab then
    if vim.api.nvim_get_current_tabpage() == tab then return end -- 已在其中：no-op
    vim.api.nvim_set_current_tabpage(tab)
    ensure_tree(tab) -- 切入时树若被手动关过则重开（设计共识）
    local dw = display_win(tab)
    if dw then focus_display(dw) end -- 焦点落显示窗，与 <C-a> toggle pane 的落点隐喻一致
    return
  end
  vim.cmd("$tabnew") -- 末尾创建：g1-g9 位置键零扰动（ADR 0005）
  local new_tab = vim.api.nvim_get_current_tabpage()
  vim.t[new_tab].agent_tab = true
  -- TabEnter 在 $tabnew 时已先于 marker 写入触发过，创建路径补撤（切换路径
  -- 由 TabEnter 钩子负责）
  pcall(vim.keymap.del, "n", "<leader>at")
  local tree_base = vim.api.nvim_tabpage_list_wins(new_tab)[1]
  local dw = build_display(new_tab, tree_base)
  M.show(agent.current_id(), false)
  vim.w[tree_base].agent_tree = true
  vim.api.nvim_win_set_width(tree_base, TREE_WIDTH)
  vim.api.nvim_set_current_win(tree_base)
  open_tree()
  focus_display(dw) -- 焦点交给显示窗（新建即对话）
end

function M.setup()
  if set_up then return end
  set_up = true
  agent.setup() -- 幂等：冷启动直接 <leader>at → 树内 a 新建，ptype/TermClose 必须就位
  agent.set_alt_viewport({ active = M.active, show = M.show, sync = sync })
  local grp = vim.api.nvim_create_augroup("agent_tab", { clear = true })
  vim.api.nvim_create_autocmd("User", {
    group = grp,
    pattern = "AgentSessionsChanged",
    callback = on_changed,
  })
  vim.api.nvim_create_autocmd("TabEnter", {
    group = grp,
    callback = function()
      if M.active() then
        pcall(vim.keymap.del, "n", "<leader>at")
        local tab = vim.api.nvim_get_current_tabpage()
        vim.schedule(function() ensure_tree(tab) end)
      elseif vim.fn.maparg("<leader>at", "n") == "" then
        map_at()
      end
    end,
  })
  if M.active() then pcall(vim.keymap.del, "n", "<leader>at") end
end

return M
