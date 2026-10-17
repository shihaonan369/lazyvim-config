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
local last_tab = nil -- TabLeave 时记录，进入 agent tab 时作为 return_tab

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

-- 空态占位 buffer：无 session 时显示窗的合法内容（领地守卫唯一豁免，
-- bufvar agent_tab_welcome 标记，ADR 0005）。用户裁决：不做欢迎页文案，
-- 空态就是空白；首开无 agent 直接新建一个（见 toggle）
local function blank_buf()
  local buf = vim.fn.bufnr("^" .. WELCOME_NAME .. "$")
  if buf == -1 then
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, WELCOME_NAME)
    vim.b[buf].agent_tab_welcome = true
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "hide"
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
  -- terminal 选项整集对齐 nvim TermOpen defaults（行号/signcolumn 空白列/
  -- foldcolumn 灰 + 都源于 vsplit 继承 LazyVim 全局值，见 apply_term_winopts）
  vim.wo[win].wrap = false
  vim.wo[win].list = false
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].foldcolumn = "0"
  pcall(vim.api.nvim_win_call, win, function() vim.cmd("clearjumps") end) -- 见 apply_term_winopts：jumplist 毒条目
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
    -- 立即换占位 buffer：vsplit 会从显示窗继承 agent terminal，而"已在别窗
    -- 显示"的 buffer 不触发 BWE、只有 sweep 盯——清退成 blank 又会落入域
    -- 守卫，两者乒乓成死循环。占位 buffer 本就在域白名单里
    vim.api.nvim_win_set_buf(win, blank_buf())
    vim.api.nvim_win_set_width(win, TREE_WIDTH)
    vim.wo[win].winfixwidth = true -- 宽度稳定（用户裁决 2026-10-15）：equalalways/
    -- wincmd =/插件 vsplit 舞步都动不了 40；主动 resize（C-S-Right）不认 fix，最大化语义保留
    vim.api.nvim_set_current_win(win)
    open_tree()
  end
end

-- 关树窗（q 与 tab 内 <leader>at 共用）。注意 neo-tree 自带的 close_window
-- 在 position=current 窗口里只清 buffer 不关窗，留下空 editor 窗且
-- agent_tree winvar 还挂着——ensure_tree 会误判树在、永远不重建（实测踩过），
-- 所以 q 由本源接管直接关窗。树是 tab 唯一窗时关窗即关 tab（marker 消失，
-- <leader>at 幂等重建）；全 nvim 只剩这一个窗则 E444 防御跳过
local function close_tree(tab)
  local win = tree_win(tab)
  if not win then return end
  if #vim.api.nvim_tabpage_list_wins(tab) == 1 and #vim.api.nvim_list_tabpages() == 1 then
    return
  end
  pcall(vim.api.nvim_win_close, win, false)
end

-- 显示窗应持有的 buffer：session buf，无 current 落空态占位
local function set_display_buf(win, id)
  local buf = (id and agent.buf_of(id)) or blank_buf()
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

-- 显示窗跟随 current；全灭转空白占位。不重建被关的窗、不夺焦点。
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

-- <leader>aa 在 agent tab 内的形态：树 toggle（关了开、开了关）。
-- 隐喻统一：aa = "给我看 agent 列表"，主 tab 是浮窗 picker，agent tab 是
-- 左侧树（用户裁决，2026-10-15）——agent_sessions.M.picker 经 alt_viewport
-- 分派到这里
function M.tree_toggle()
  local tab = M.tab()
  if not tab then return end
  if tree_win(tab) then
    close_tree(tab)
  else
    ensure_tree(tab)
  end
end

-- agent tab 只收 agent 域（用户裁决 2026-10-15）：file buffer 等落进树窗/
-- 显示窗，挪回来源 tab 主区并带视角过去；被污染的本职窗口复原（树窗重建、
-- 显示窗 sync）。缓冲区点击/`:buffer`/picker 兜底等入口一概同路
local function redirect(tab, win, buf)
  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(buf) then return end
    -- 来源 tab：toggle/TabEnter 记录的来路，失效则退而取首个非 agent tab
    local target_tab = vim.t[tab].return_tab
    if not (target_tab and vim.api.nvim_tabpage_is_valid(target_tab)) then
      for _, t in ipairs(vim.api.nvim_list_tabpages()) do
        if t ~= tab then target_tab = t break end
      end
    end
    if not target_tab then return end -- 全 nvim 只剩本 tab：无处可去，放行
    local target -- 来源 tab 的首个普通窗；无则 vsplit 出一个
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(target_tab)) do
      local cfg = vim.api.nvim_win_get_config(w)
      if cfg.relative == "" and not vim.w[w].agent_pane and not vim.w[w].shell_term and not vim.w[w].agent_tree then
        target = w
        break
      end
    end
    if not target then
      vim.api.nvim_set_current_tabpage(target_tab)
      vim.cmd("leftabove vsplit")
      target = vim.api.nvim_get_current_win()
    end
    vim.api.nvim_win_set_buf(target, buf)
    -- 复原本职窗口。可重入：set_buf 会再触发一轮 on_buf_enter（此刻污染窗
    -- 还在显示该 buffer），前一轮已把它清退——win 失效即无事可做
    if vim.api.nvim_win_is_valid(win) then
      if vim.w[win].agent_tree == true then
        pcall(vim.api.nvim_win_close, win, false) -- 树若成唯一窗：连带关 tab，幂等可重建
        if vim.api.nvim_tabpage_is_valid(tab) then ensure_tree(tab) end
      else
        sync() -- 显示窗回 current/空白占位
      end
    end
    -- 用户点 buffer 的意图是看它：视角跟过去
    vim.api.nvim_set_current_tabpage(target_tab)
    vim.api.nvim_set_current_win(target)
  end)
end

-- 本职窗口 = 树窗或显示窗；只有它们收 buffer 入住检查（tab 内的过渡 scratch
-- 窗不折腾——$tabnew 的 [No Name] 等着 open_tree 换掉它）
local function is_work_win(tab, win)
  return vim.w[win].agent_tree == true or win == vim.t[tab].agent_display
end

local function on_buf_enter(args)
  local tab = M.tab()
  if not tab then return end
  local buf = args.buf
  if vim.b[buf].agent_session or vim.b[buf].agent_tab_welcome then return end
  if vim.bo[buf].filetype == "neo-tree" then return end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
    if vim.api.nvim_win_is_valid(win)
      and vim.api.nvim_win_get_buf(win) == buf
      and is_work_win(tab, win)
    then
      redirect(tab, win, buf)
      return
    end
  end
end

-- agent tab 内撤除的键（离开恢复）：<leader>at 本体 + <leader>as——Smart Add
-- 的"把文件上下文加给 agent"在 tab 里语义落空（用户裁决 2026-10-15）。as 定义
-- 分散在三个 agent spec 且各异（expr/多 mode），首次撤除前捕获原映射、
-- 离开时原样重放
local hidden_keys = {} -- [lhs] = { [mode] = maparg dict }

local function hide_keys()
  for _, lhs in ipairs({ "<leader>as" }) do
    hidden_keys[lhs] = hidden_keys[lhs] or {}
    for _, mode in ipairs({ "n", "v", "x" }) do
      local m = vim.fn.maparg(lhs, mode, false, true)
      if type(m) == "table" and m.callback ~= nil and hidden_keys[lhs][mode] == nil then
        hidden_keys[lhs][mode] = m
      end
      pcall(vim.keymap.del, mode, lhs)
    end
  end
end

-- agent tab 内不列 file buffer 标签（用户裁决 2026-10-15；tab 页标签保留）。
-- 不动 showtabline（一刀切会把 tab 标签也藏掉）——过滤交给 bufferline 的
-- custom_filter（见 lua/plugins/bufferline.lua），tabline 随 TabEnter 自然重绘
local function restore_keys()
  for lhs, mods in pairs(hidden_keys) do
    for mode, m in pairs(mods) do
      if vim.fn.maparg(lhs, mode) == "" then
        vim.keymap.set(mode, lhs, m.callback, {
          desc = m.desc,
          expr = m.expr == 1,
          silent = m.silent == 1,
          nowait = m.nowait == 1,
        })
      end
    end
  end
end

-- <leader>at：agent tab 内撤映射（no-op 且 which-key 不列不可用键），离开恢复
local function map_at()
  vim.keymap.set("n", "<leader>at", function() M.toggle() end, { desc = "Agent tab", silent = true })
end

function M.toggle()
  local tab = M.tab()
  if tab then
    if vim.api.nvim_get_current_tabpage() == tab then return end -- 已在其中：no-op
    vim.t[tab].return_tab = vim.api.nvim_get_current_tabpage() -- 记录来路（域守卫挪 buffer 用）
    vim.api.nvim_set_current_tabpage(tab)
    ensure_tree(tab) -- 切入时树若被手动关过则重开（设计共识）
    local dw = display_win(tab)
    if dw then focus_display(dw) end -- 焦点落显示窗，与 <C-a> toggle pane 的落点隐喻一致
    return
  end
  vim.cmd("$tabnew") -- 末尾创建：g1-g9 位置键零扰动（ADR 0005）
  vim.bo.buflisted = false -- 树位 [No Name] 不算导航目标：listed 会污染 bufferline/tabline 的 buffer 计数
  local new_tab = vim.api.nvim_get_current_tabpage()
  vim.t[new_tab].agent_tab = true
  -- TabEnter 在 $tabnew 时已先于 marker 写入触发过，创建路径补撤（切换路径
  -- 由 TabEnter 钩子负责）
  pcall(vim.keymap.del, "n", "<leader>at")
  hide_keys()
  local tree_base = vim.api.nvim_tabpage_list_wins(new_tab)[1]
  local dw = build_display(new_tab, tree_base)
  -- 首开无 agent：直接新建一个（用户裁决，替代欢迎页）；有则显示 current
  if agent.current_id() then
    M.show(agent.current_id(), false)
  else
    agent.new()
  end
  vim.w[tree_base].agent_tree = true
  vim.api.nvim_win_set_width(tree_base, TREE_WIDTH)
  vim.wo[tree_base].winfixwidth = true -- 同 ensure_tree：宽度稳定，只有手动 resize 可变
  vim.api.nvim_set_current_win(tree_base)
  open_tree()
  focus_display(dw) -- 焦点交给显示窗（新建即对话）
end

function M.setup()
  if set_up then return end
  set_up = true
  agent.setup() -- 幂等：冷启动直接 <leader>at → 树内 a 新建，ptype/TermClose 必须就位
  agent.set_alt_viewport({
    active = M.active,
    show = M.show,
    sync = sync,
    picker = M.tree_toggle,
    -- 显示窗的入侵由本模块接管（file buffer 挪回来源 tab），agent_sessions
    -- 的 relocate 不再处理（树窗是领地，tab 内无重定向目标，ADR 0005）
    claims = function(win)
      local tab = M.tab()
      return tab ~= nil and win == display_win(tab)
    end,
  })
  local grp = vim.api.nvim_create_augroup("agent_tab", { clear = true })
  vim.api.nvim_create_autocmd("User", {
    group = grp,
    pattern = "AgentSessionsChanged",
    callback = on_changed,
  })
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = grp,
    callback = on_buf_enter, -- agent tab 只收 agent 域：file buffer 挪回来源 tab
  })
  -- 窗口出生记录仪（诊断"显示窗偶发变窄"的触发源，用户尚不清楚条件）：
  -- agent tab 内每次开窗，把创建栈回溯落进 run 目录日志。抓到真凶后可移除
  vim.api.nvim_create_autocmd("WinNew", {
    group = grp,
    callback = function()
      local tab = vim.api.nvim_get_current_tabpage()
      if not is_agent_tab(tab) then return end
      local log = vim.fn.stdpath("run") .. "/agent-tab-winnew.log"
      local fh = io.open(log, "a")
      if not fh then return end
      fh:write(os.date("%H:%M:%S") .. " WinNew wins=" .. #vim.api.nvim_tabpage_list_wins(tab)
        .. " display_w=" .. (display_win(tab) and vim.api.nvim_win_get_width(display_win(tab)) or "?")
        .. "\n" .. debug.traceback() .. "\n")
      fh:close()
    end,
  })
  vim.api.nvim_create_autocmd("TabLeave", {
    group = grp,
    callback = function()
      last_tab = vim.api.nvim_get_current_tabpage()
    end,
  })
  vim.api.nvim_create_autocmd("TabEnter", {
    group = grp,
    callback = function()
      if M.active() then
        pcall(vim.keymap.del, "n", "<leader>at")
        hide_keys()
        local tab = vim.api.nvim_get_current_tabpage()
        if last_tab and last_tab ~= tab then vim.t[tab].return_tab = last_tab end
        vim.schedule(function()
          ensure_tree(tab)
          -- 离场补齐：manager.refresh 只刷新当前 tab 的树状态，人在主 tab
          -- pane 上 </> 切换时 agent tab 的树只被记 dirty，回来此刻对齐
          -- 当下（含光标跟随，见 agent_tree.navigate）
          pcall(function() require("neo-tree.sources.manager").refresh("agent_tree") end)
        end)
      else
        if vim.fn.maparg("<leader>at", "n") == "" then map_at() end
        restore_keys()
      end
    end,
  })
  if M.active() then
    pcall(vim.keymap.del, "n", "<leader>at")
    hide_keys()
  end
end

return M
