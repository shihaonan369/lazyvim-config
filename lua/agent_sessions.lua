-- agent_sessions: 多 agent session 管理（设计见 docs/adr/0001）
-- 单一 agent pane（右侧 30%），session = 后台存活的 terminal buffer。
local M = {}

local PANE_WIDTH = 0.30

-- 图标：表情 = 状态（与颜色双编码），实心/空心孪生 = 当前/后台角色。
-- working=robot_excited（干得起劲）、idle=robot_happy（心满意足交差）、
-- attention=robot_confused（问号脸等拍板），各带 outline 空心孪生（后台）。
-- 无事件（机器侧 hook 未配置）无表情，落回 robot（U+F06A9）/ robot_outline
-- （U+F167A）对（<leader>a 分组同款）——"未知"与"睡觉"是两个概念两个图标。
-- angry/dead/love 有字形无状态可挂，刻意不用（图标与状态 1:1，不为图标开
-- 新状态）。格子属性(下划线/反色)对不齐 PUA 大字形向右溢出的墨迹，同走
-- 溢出规则的字形才天然对称(docs/adr/0003)
local STATE_ICON = {
  working = { vim.fn.nr2char(0xF16A3), vim.fn.nr2char(0xF16A4) }, -- excited 实心/空心
  idle = { vim.fn.nr2char(0xF1719), vim.fn.nr2char(0xF171A) }, -- happy 实心/空心
  attention = { vim.fn.nr2char(0xF169F), vim.fn.nr2char(0xF16A0) }, -- confused 实心/空心
}
local NEUTRAL_ICON = { vim.fn.nr2char(0xF06A9), vim.fn.nr2char(0xF167A) } -- robot 对（无事件）
-- 睡觉（nf-md-robot_off）：pane 收起时逐 session 替代表情（docs/adr/0003）
local ROBOT_OFF = vim.fn.nr2char(0xF16A7)

local S = {
  ptype = nil,      -- "claude" | "codex" | "opencode"
  sessions = {},    -- { { id, bufnr, job_id, pid, tag, state } }
  current = nil,    -- session id
  pane_win = nil,   -- winid
  next_id = 1,
  augroup = nil,
  intent = "show",  -- claude provider 桥接: "show" | "new"
  claude_cache = nil, -- { cmd_list, env }
  override_once = false, -- pick_win 显式选 pane 的一次性放行（docs/adr/0002）
  follow_buf = nil, -- 领地入侵后待兑现的焦点跟随（buffer 落定在非领地窗口时送达）
}

local function by_id(id)
  for i, s in ipairs(S.sessions) do
    if s.id == id then return i, s end
  end
end

local function by_buf(bufnr)
  for i, s in ipairs(S.sessions) do
    if s.bufnr == bufnr then return i, s end
  end
end

local function emit()
  vim.schedule(function()
    vim.cmd("redrawstatus")
    pcall(vim.api.nvim_exec_autocmds, "User", { pattern = "AgentSessionsChanged" })
  end)
end

local function pane_valid()
  return S.pane_win
    and vim.api.nvim_win_is_valid(S.pane_win)
    and vim.api.nvim_win_get_tabpage(S.pane_win) == vim.api.nvim_get_current_tabpage()
end

local function pane_focused()
  return pane_valid() and vim.api.nvim_get_current_win() == S.pane_win
end

-- pane 是否开着（跨 tab：同步语义用这个，toggle/hide 语义仍用 pane_valid
-- 的同 tab 判定）——agent tab 视口在场时，主 tab 的 pane 也要跟随 current 换
-- buffer（单一 current、所有显示窗同步，docs/adr/0005）
local function pane_open()
  return S.pane_win
    and vim.api.nvim_win_is_valid(S.pane_win)
    and vim.w[S.pane_win].agent_pane == true
end

-- 备用视口注册口（agent_tab 注册 active/show；未注册时行为与本决定之前逐字
-- 相同）。session 池不感知具体视口，display 只按"当前 tab 是否备用视口"路由
local alt_viewport = nil

local function show_pane()
  if not pane_valid() then
    local width = math.floor(vim.o.columns * PANE_WIDTH)
    vim.cmd("botright " .. width .. "vsplit")
    S.pane_win = vim.api.nvim_get_current_win()
    vim.w[S.pane_win].agent_pane = true -- 窗口身份标记，winvar 随窗口存亡（docs/adr/0002）
  end
  local _, cur = by_id(S.current)
  if cur then vim.api.nvim_win_set_buf(S.pane_win, cur.bufnr) end
end

local function hide_pane()
  if pane_valid() then
    if pane_focused() then vim.cmd("stopinsert") end
    if #vim.api.nvim_tabpage_list_wins(vim.api.nvim_win_get_tabpage(S.pane_win)) > 1 then
      vim.api.nvim_win_close(S.pane_win, false)
    else
      -- 唯一窗口关不得（E444）：领地交还、buffer 换出（否则窗口继续渲染
      -- 后台 session，pane 复活时两窗同显一个 terminal），指针清空，
      -- 下次 show_pane 另立新窗（初始宽度）
      vim.w[S.pane_win].agent_pane = nil
      pcall(vim.api.nvim_win_call, S.pane_win, function() vim.cmd("enew") end)
    end
  end
  S.pane_win = nil
end

-- 不变量：终端领地窗口只放 terminal buffer --------------------------------
-- agent pane 与底部 shell 终端都是"领地"：一切"打开 buffer"的 nvim 语义都指向
-- 当前窗口，且 snacks picker main 的兜底分支在布局中无文件窗口时也会把 terminal
-- 窗口当目标（实测复现）。领地必须在窗口层自守：非 terminal buffer 无论经何入口
-- 进入（:e / gf / picker 兜底 / API set_buf），立即搬到主区，领地恢复 terminal，
-- 焦点跟随文件。见 docs/adr/0002。
-- 标记两种：agent pane（winvar agent_pane，合法集 = agent session buffer）；
-- 底部 shell（winvar shell_term，由 TermOpen/BWE 按 buftype==terminal 自动标记
-- 非 agent、非浮窗的宿主窗口，hide/show 换窗口后自愈，合法集 = 任意 terminal buffer）。

local function is_agent_buf(buf)
  return vim.api.nvim_buf_is_valid(buf) and vim.b[buf].agent_session == true
end

-- pane 应恢复显示的 buffer：当前 session 优先，模块状态失联时退而求其次
local function pane_restore_buf()
  local _, cur = by_id(S.current)
  if cur and vim.api.nvim_buf_is_valid(cur.bufnr) then return cur.bufnr end
  for _, s in ipairs(S.sessions) do
    if vim.api.nvim_buf_is_valid(s.bufnr) then return s.bufnr end
  end
end

-- 重定向目标：当前 tabpage 最左/最上的普通窗口；领地独占时按几何形态新开主区窗口。
-- 用窗口坐标而非 winnr 编号：编号跟创建/关闭历史走，不保证等于空间左上角。
-- 领地三种：agent pane（合法集 = agent session buffer）、底部 shell（任意
-- terminal）、agent tab 树窗（合法集 = agent_tree 树 buffer，ADR 0005）——
-- 树窗若不算领地，file buffer 进显示窗时 main_target_win 会把它"救"进树窗
local function is_territory(win)
  return vim.w[win].agent_pane == true or vim.w[win].shell_term == true or vim.w[win].agent_tree == true
end

local function main_target_win(pane)
  local best, best_row, best_col
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if w ~= pane and vim.api.nvim_win_is_valid(w) and not is_territory(w)
      and vim.api.nvim_win_get_config(w).relative == "" then
      local row, col = unpack(vim.api.nvim_win_get_position(w))
      if not best or row < best_row or (row == best_row and col < best_col) then
        best, best_row, best_col = w, row, col
      end
    end
  end
  if best then return best end
  local win
  vim.api.nvim_win_call(pane, function()
    if vim.w[0].agent_pane then
      -- pane 让位恒走 vsplit 回右侧正统槽位：宽度可以让回 30%（set_width
      -- 在纯水平 frame 里是几何空转，"上方开窗"分支会让最大化 pane 让位
      -- 后仍占全宽；按领地身份判分支而非宽度——宽度 ≥ columns-2 也可能是
      -- 最大化 pane，全宽只是它的瞬时形态）
      vim.cmd("leftabove vsplit") -- 主区开在左方，保住 pane 居右
    elseif vim.api.nvim_win_get_width(0) >= vim.o.columns - 2 then
      vim.cmd("aboveleft split") -- 底部 shell 全宽：主区开在上方
    else
      vim.cmd("leftabove vsplit")
    end
    win = vim.api.nvim_get_current_win()
  end)
  if vim.w[pane].agent_pane then
    vim.api.nvim_win_set_width(pane, math.floor(vim.o.columns * PANE_WIDTH))
    -- 让位 = 系统取消最大化：清掉 toggle_max_width 的还原值（keymaps.lua
    -- 拥有该 winvar），否则下次 <C-S-Right> 会还原到陈旧宽度而非重新拉满
    vim.w[pane].max_width = nil
  end
  return win
end

-- 焦点跟随：buffer 已由第三方挪到唯一非领地窗口时，把焦点送到文件处
local function follow_buf(buf)
  local host
  for _, w in ipairs(vim.fn.win_findbuf(buf)) do
    if vim.api.nvim_win_is_valid(w) and not is_territory(w) then
      if host then return end -- 显示在多个窗口，不猜
      host = w
    end
  end
  if host then pcall(vim.api.nvim_set_current_win, host) end
end

local relocating = false
local function relocate(pane, buf, restore)
  if relocating then return end
  if S.override_once then
    S.override_once = false -- pick_win 显式选领地：放行一次
    return
  end
  if not (restore and vim.api.nvim_buf_is_valid(restore)) then
    vim.w[pane].agent_pane = nil -- 无 terminal buffer 可守，领地名存实亡，交还 nvim
    vim.w[pane].shell_term = nil
    return
  end
  relocating = true
  -- 触发命令（:e / :buffer 等）的收尾会改写原窗口的 buffer 和焦点，
  -- 重定向必须整段命令出栈后再执行，否则会被收尾覆盖
  vim.schedule(function()
    local function body()
      if not vim.api.nvim_win_is_valid(pane) or not is_territory(pane) then
        follow_buf(buf) -- 领地窗口已消失（第三方关闭/接管），焦点仍要跟到文件处
        return
      end
      if vim.api.nvim_win_get_buf(pane) ~= buf then
        -- 入侵已被第三方同步接管（snacks terminal 会对自家窗口自动挪移文件）：
        -- buffer 搬运不重做，但"焦点跟随文件"的承诺仍要兑现
        follow_buf(buf)
        return
      end
      local target = main_target_win(pane)
      if target and vim.api.nvim_win_is_valid(target) then
        if vim.api.nvim_win_get_buf(target) ~= buf then
          vim.api.nvim_win_set_buf(target, buf)
        end
        pcall(vim.api.nvim_set_current_win, target) -- 焦点跟随文件
      end
      vim.api.nvim_win_set_buf(pane, restore)
    end
    body()
    relocating = false -- 末尾复位：回调期间自身 set_buf 触发的 BWE 不得再次进入重定
  end)
end

-- 守卫随模块加载即武装（模块经 lualine / 插件 spec 在启动时必然加载）
local invariant = vim.api.nvim_create_augroup("agent_sessions_invariant", { clear = true })

-- TermOpen 兜底标记：snacks 先开窗显示 buffer、之后才 termopen，
-- 开窗时的 BWE 里 buftype 还不是 terminal，标记会漏；terminal 身份落地时补标
local function mark_shell_territory(buf)
  if not vim.api.nvim_buf_is_valid(buf) or vim.b[buf].agent_session then return end
  if vim.bo[buf].buftype ~= "terminal" then return end
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_config(win).relative == "" then
      vim.w[win].shell_term = true
      vim.w[win].territory_buf = buf
    end
  end
end
vim.api.nvim_create_autocmd("TermOpen", {
  group = invariant,
  callback = function(args)
    mark_shell_territory(args.buf)
  end,
})
vim.api.nvim_create_autocmd("BufWinEnter", {
  group = invariant,
  callback = function(args)
    local buf = args.buf
    local is_term = vim.bo[buf].buftype == "terminal"
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
        -- 注意：vim.w[win] 取的是快照，必须穿透赋值（vim.w[win].x = y）才能写回
        if vim.w[win].agent_pane then
          -- agent tab 显示窗的入侵由 tab 视口接管（file buffer 挪回来源
          -- tab，本 tab 内无重定向目标——树窗也是领地，ADR 0005）
          if alt_viewport and alt_viewport.claims and alt_viewport.claims(win) then
            return
          end
          -- 欢迎页豁免：agent tab 空态时右窗合法持有非 terminal buffer，
          -- 是领地"只放 terminal"的唯一例外（docs/adr/0005）
          if not is_agent_buf(buf) and not vim.b[buf].agent_tab_welcome then
            S.follow_buf = buf
            relocate(win, buf, pane_restore_buf())
          end
        elseif vim.w[win].shell_term then
          if is_term then
            vim.w[win].territory_buf = buf -- 记住领地当前 terminal，入侵时用它恢复
          else
            S.follow_buf = buf
            relocate(win, buf, vim.w[win].territory_buf)
          end
        elseif is_agent_buf(buf)
          and vim.api.nvim_win_get_config(win).relative == ""
        then
          -- 反向入侵：agent session buffer 落进非领地窗口（split 克隆、
          -- :buffer 等，实际触发路径不明——机制层兜底、入口无关，与正向
          -- 守卫同一哲学）。editor 窗口不收留 session buffer：交还空白，
          -- session 归视口。触发命令的收尾会改写窗口 buffer，清退须整段
          -- 命令出栈后延迟执行（同 relocate 的时序）。shell 领地合法集是
          -- 任意 terminal，agent buffer 落底部 shell 窗口不算入侵
          vim.schedule(function()
            if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
              pcall(vim.api.nvim_win_call, win, function() vim.cmd("enew") end)
            end
          end)
        elseif
          is_term
          and not vim.b[buf].agent_session
          and vim.api.nvim_win_get_config(win).relative == ""
        then
          -- 普通 terminal（底部 shell 等）在普通窗口上屏即标记领地
          -- （hide/show 会换窗口，标记随 BWE 自愈；浮窗不入领地，
          -- 且不能用 filetype=snacks_terminal 判定——BWE 时 snacks 还没设上）
          vim.w[win].shell_term = true
          vim.w[win].territory_buf = buf
        elseif S.follow_buf == buf and not is_term then
          -- 被挪移的文件最终落定在非领地窗口：兑现焦点跟随
          -- （snacks 对自家 terminal 的挪移是多步异步的，落定才是送达时机）
          S.follow_buf = nil
          vim.schedule(function()
            pcall(vim.api.nvim_set_current_win, win)
          end)
        end
      end
    end
  end,
})

-- 反向入侵清查：agent session buffer 只许住在领地窗口。split 克隆、:buffer
-- 等"buffer 已在别窗显示"的路径不触发 BufWinEnter（实测），靠 WinNew/
-- WinEnter/BufEnter 兜底全窗扫描（入口无关）。清退延后出栈执行（同 relocate）
local function sweep_strays()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win)
      and vim.api.nvim_win_get_config(win).relative == ""
      and not is_territory(win)
      and is_agent_buf(vim.api.nvim_win_get_buf(win))
    then
      local buf = vim.api.nvim_win_get_buf(win)
      vim.schedule(function()
        if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
          pcall(vim.api.nvim_win_call, win, function() vim.cmd("enew") end)
        end
      end)
    end
  end
end
vim.api.nvim_create_autocmd({ "WinNew", "WinEnter", "BufEnter" }, {
  group = invariant,
  callback = sweep_strays,
})

local function display(id, focus)
  S.current = id
  local in_alt = alt_viewport and alt_viewport.active()
  if not in_alt and not pane_valid() then
    show_pane()
  end
  local _, cur = by_id(id)
  if cur and pane_open() then
    vim.api.nvim_win_set_buf(S.pane_win, cur.bufnr) -- pane 恒显 current（跨 tab 同步，ADR 0005）
  end
  if in_alt then
    alt_viewport.show(id, focus) -- agent tab 右窗同步（含焦点/insert）
  elseif focus then
    vim.api.nvim_set_current_win(S.pane_win)
    vim.cmd("startinsert")
  end
  emit()
end

-- tmux 身份剥除：nvimdc 工作流里 nvim 跑在 tmux 内，termopen 子进程会继承
-- TMUX。claude/codex/opencode 看到 TMUX 就把终端查询与剪贴板输出写成 tmux
-- passthrough DCS，而 nvim terminal 解不了 DCS，内层载荷（如 OSC11 背景色
-- 查询的 "11;?"）会泄漏成字面文本渲染进 pane。agent session 的宿主是
-- nvim terminal 而非 tmux，env 必须陈述这个事实（scripts/repro-osc-leak.sh）。
local function scrub_tmux_env(env)
  local e = vim.tbl_extend("force", env or {}, { TMUX = "", TMUX_PANE = "" })
  if e.TERM_PROGRAM == "tmux" then
    e.TERM_PROGRAM, e.TERM_PROGRAM_VERSION = "", ""
  end
  return e
end

-- agent 状态事件管线（docs/adr/0003）--------------------------------------
-- spawn 给 agent 注入 AGENT_SESSION_TAG / AGENT_STATUS_FILE；claude/codex 的
-- hooks（scripts/agent-status-hook.sh，状态词由各家 hook 配置的 argv 写死）与
-- opencode 插件把归一化事件 {"tag":…,"state":…} 单行追加进本实例的事件邮箱；
-- 这里用 luv fs_event 监听追加、按 tag 归因到 session。全程事件驱动零轮询，
-- 状态挂在 session 上随 TermClose 消失；机器侧 hook 未配置时状态恒为 nil，
-- statusline 呈中性色，不报错。

-- 状态配色：借现成主题组（repo 惯例），实测须在两套生效主题（tokyonight 暗底
-- #1a1b26 / catppuccin-latte 亮底 #eff1f5，statusline 透明故按主题 base bg）下
-- 都满足 WCAG ≥3:1。语义首选反而落选：DiagnosticWarn 橙 latte 仅 2.31、
-- DiagnosticOk 绿 latte 2.96、Special 粉 latte 2.34、Comment 灰 tokyo 2.76。
-- 入选：Function 蓝 6.79/4.34、Character 绿青 9.35/3.31、
-- DiagnosticError 红 4.17/4.80、ModeMsg 灰 8.10/7.06（数据见 docs/adr/0003）。
local STATE_HL = {
  working = "Function",
  idle = "Character",
  attention = "DiagnosticError",
}

local HL_NEUTRAL = "ModeMsg" -- 无事件（机器侧 hook 未配置）时的中性色


local status_watcher = {
  file = nil,   -- 事件邮箱路径（每 nvim 实例一个，退出时删除）
  handle = nil, -- luv fs_event
  offset = 0,   -- 已消费字节数
  partial = "", -- 无换行的残行（留待下次事件续读）
}

local function status_file()
  -- stdpath("run") 是本实例私有临时目录，天然按实例隔离，孤儿由系统清理
  return vim.fn.stdpath("run") .. "/agent-status.jsonl"
end

local function status_apply(line)
  local ok, ev = pcall(vim.json.decode, line)
  if not ok or type(ev) ~= "table" then return end
  if not STATE_HL[ev.state] then return end -- 只认统一状态词表
  for _, s in ipairs(S.sessions) do
    if s.tag == ev.tag then
      s.state = ev.state
      return
    end
  end
end

local function status_drain()
  local w = status_watcher
  local fd = vim.uv.fs_open(w.file, "r", 384) -- 0600
  if not fd then return end
  local stat = vim.uv.fs_fstat(fd)
  if stat then
    if stat.size < w.offset then w.offset, w.partial = 0, "" end -- 截断兜底
    if stat.size > w.offset then
      local data = vim.uv.fs_read(fd, stat.size - w.offset, w.offset)
      if data then
        w.offset = w.offset + #data
        w.partial = w.partial .. data
        while true do
          local nl = w.partial:find("\n", 1, true)
          if not nl then break end
          status_apply(w.partial:sub(1, nl - 1))
          w.partial = w.partial:sub(nl + 1)
        end
      end
    end
  end
  vim.uv.fs_close(fd)
end

local function status_watch_start()
  if status_watcher.handle then return end
  local file = status_file()
  local fd = vim.uv.fs_open(file, "a", 384) -- 0600；邮箱先落地，fs_event 只认既有路径
  if fd then vim.uv.fs_close(fd) end
  status_watcher.file = file
  status_watcher.handle = vim.uv.new_fs_event()
  status_watcher.handle:start(file, {}, vim.schedule_wrap(function()
    status_drain()
    emit()
  end))
end

local function spawn(cmd_list, env)
  local sess = { id = S.next_id, bufnr = nil, job_id = nil, pid = nil, tag = nil, state = nil }
  S.next_id = S.next_id + 1
  sess.tag = vim.fn.getpid() .. "." .. sess.id -- 状态事件归因（docs/adr/0003）

  local prev_win = vim.api.nvim_get_current_win()
  -- pane 先立起来：termopen 需要一个当前 buffer，session 建好即显示。
  -- agent tab 内新建走备用视口：pane 不立（立了会砸坏 tab 布局，ADR 0005），
  -- buffer 直接上 tab 右窗，termopen 用 buf_call 在无宿主窗的 buffer 上执行
  sess.bufnr = vim.api.nvim_create_buf(false, true)
  vim.b[sess.bufnr].agent_session = true -- buffer 身份标记：pane 不变量只认它（docs/adr/0002）
  table.insert(S.sessions, sess) -- TermOpen 回调依赖 registry 已登记
  S.current = sess.id
  local in_alt = alt_viewport and alt_viewport.active()
  if in_alt then
    alt_viewport.show(sess.id, false)
  else
    show_pane()
    vim.api.nvim_win_set_buf(S.pane_win, sess.bufnr)
  end

  status_watch_start() -- 邮箱先立起来，agent 启动期的事件不丢
  local opts = {
    cwd = vim.fn.getcwd(),
    env = vim.tbl_extend("force", scrub_tmux_env(env), {
      AGENT_SESSION_TAG = sess.tag,
      AGENT_STATUS_FILE = status_file(),
    }),
  }
  if in_alt then
    vim.api.nvim_buf_call(sess.bufnr, function()
      sess.job_id = vim.fn.termopen(cmd_list, opts)
    end)
  else
    -- termopen 挂在当前 buffer 上：pane 复用（未走 vsplit）时焦点可能在主区，
    -- 必须临时切到 pane 执行，否则会劫持主区当前 buffer
    vim.api.nvim_win_call(S.pane_win, function()
      sess.job_id = vim.fn.termopen(cmd_list, opts)
    end)
  end
  vim.bo[sess.bufnr].bufhidden = "hide"
  local ok, pid = pcall(vim.fn.jobpid, sess.job_id)
  if ok then sess.pid = pid end

  -- vsplit 会把光标带进 pane，交还给调用方决定焦点
  if vim.api.nvim_win_is_valid(prev_win) and prev_win ~= S.pane_win then
    vim.api.nvim_set_current_win(prev_win)
  end
  emit()
  return sess
end

-- CLAUDE_CODE_NO_FLICKER=1 让 claude 以 fullscreen TUI（alternate screen）渲染；
-- 仅作用于本系统 spawn 的进程，不影响终端里直接跑的 claude
local function claude_spawn_env(env)
  return vim.tbl_extend("force", env or {}, { CLAUDE_CODE_NO_FLICKER = "1" })
end

-- claude 专属启动参数注入：--settings 挂 agent 状态 hooks
-- （scripts/agent-status-settings.json，随本仓库走，只作用于这里 spawn 的
-- claude，不污染全局 ~/.claude/settings.json）；沙箱（IS_SANDBOX=1）再追加
-- bypassPermissions（新版写法，替代 --dangerously-skip-permissions）
local CLAUDE_STATUS_SETTINGS = vim.fn.stdpath("config") .. "/scripts/agent-status-settings.json"

local function claude_spawn_cmd(cmd_list)
  if not vim.fn.fnamemodify(cmd_list[1], ":t"):find("claude", 1, true) then
    return cmd_list -- 非 claude 命令（如测试用 /bin/sleep 冒充）不注入
  end
  local out = vim.deepcopy(cmd_list)
  if not vim.tbl_contains(out, "--settings") then
    vim.list_extend(out, { "--settings", CLAUDE_STATUS_SETTINGS })
  end
  if vim.env.IS_SANDBOX == "1" and not vim.tbl_contains(out, "--permission-mode") then
    vim.list_extend(out, { "--permission-mode", "bypassPermissions" })
  end
  return out
end

-- 适配层 ---------------------------------------------------------------

local adapters = {}

adapters.codex = {
  new = function()
    local sess = spawn({ "codex" }, {})
    display(sess.id, true)
  end,
}

adapters.opencode = {
  new = function()
    -- 与 opencode.nvim 默认 server.toggle 一致的启动命令
    local sess = spawn({ "opencode", "--port" }, {})
    display(sess.id, true)
  end,
}

adapters.claude = {
  new = function()
    if S.claude_cache then
      local base = { S.claude_cache.cmd_list[1] }
      local sess = spawn(claude_spawn_cmd(base), S.claude_cache.env)
      display(sess.id, true)
    else
      -- provider 从未被调过，让插件自己构造 cmd/env 走一次 provider.open
      S.intent = "new"
      vim.cmd("ClaudeCode")
    end
  end,
}

-- claude provider 桥接入口（由 claudecode.lua 的 provider table 调用）
function M.claude_open(cmd_string, env, focus)
  local cmd_list = vim.split(cmd_string, "%s+")
  env = claude_spawn_env(env)
  S.claude_cache = { cmd_list = cmd_list, env = env }
  local wants_new = S.intent == "new" or #cmd_list > 1
  S.intent = "show"
  if wants_new or #S.sessions == 0 then
    local sess = spawn(claude_spawn_cmd(cmd_list), env)
    display(sess.id, focus ~= false)
  else
    display(S.current, focus ~= false)
  end
end

function M.claude_toggle(cmd_string, env, focus_mode)
  -- 此处不加 agent tab 护栏：树内 a 的冷启动（无 claude_cache）经
  -- :ClaudeCode → provider 进来，掐断会令 tab 内首次新建永远无声失败。
  -- tab 场景由收尾的 display() 路由到右窗；pane_valid 跨 tab 判假，
  -- 永远走 else 分支，不会在 tab 内另立 pane（用户键 <C-a> 走 M.toggle
  -- 的护栏）。ADR 0005
  local cmd_list = vim.split(cmd_string, "%s+")
  env = claude_spawn_env(env)
  S.claude_cache = { cmd_list = cmd_list, env = env }
  local wants_new = S.intent == "new" or #cmd_list > 1
  S.intent = "show"

  if wants_new or #S.sessions == 0 then
    local sess = spawn(claude_spawn_cmd(cmd_list), env)
    display(sess.id, true)
    return
  end
  if pane_valid() and (not focus_mode or pane_focused()) then
    hide_pane()
  else
    display(S.current, focus_mode)
  end
end

-- 公开 API -------------------------------------------------------------

function M.setup()
  if S.augroup then return end
  S.augroup = vim.api.nvim_create_augroup("agent_sessions", { clear = true })
  S.ptype = vim.g.ai_assistant

  vim.api.nvim_create_autocmd("TermOpen", {
    group = S.augroup,
    callback = function(args)
      if not by_buf(args.buf) then return end
      local bopts = { buffer = args.buf, silent = true }
      vim.keymap.set("n", "<", function() M.cycle(-1) end,
        vim.tbl_extend("force", bopts, { desc = "Agent session prev" }))
      vim.keymap.set("n", ">", function() M.cycle(1) end,
        vim.tbl_extend("force", bopts, { desc = "Agent session next" }))

      if S.ptype == "opencode" then
        local cmd = require("opencode").command
        vim.keymap.set("n", "<C-u>", function() cmd("session.half.page.up") end,
          vim.tbl_extend("force", bopts, { desc = "Scroll up half page" }))
        vim.keymap.set("n", "<C-d>", function() cmd("session.half.page.down") end,
          vim.tbl_extend("force", bopts, { desc = "Scroll down half page" }))
        vim.keymap.set("n", "gg", function() cmd("session.first") end,
          vim.tbl_extend("force", bopts, { desc = "Go to first message" }))
        vim.keymap.set("n", "G", function() cmd("session.last") end,
          vim.tbl_extend("force", bopts, { desc = "Go to last message" }))
        vim.keymap.set("n", "<Esc>", function() cmd("session.interrupt") end,
          vim.tbl_extend("force", bopts, { desc = "Interrupt session" }))
      end
    end,
  })

  vim.api.nvim_create_autocmd("TermClose", {
    group = S.augroup,
    callback = function(args)
      local idx = by_buf(args.buf)
      if not idx then return end
      local sess = S.sessions[idx]
      local was_current = sess.id == S.current
      local visible = pane_valid()
      vim.schedule(function()
        local cur_idx = by_buf(args.buf)
        if not cur_idx then return end
        table.remove(S.sessions, cur_idx)
        -- 先安顿 pane（换下一个 session / 收起），最后才删死 buffer：
        -- bd! 删正显示中的 buffer 会连带关窗（非最后窗口时），pane 若在此刻
        -- 失窗，show_pane 会按初始 30% 重建——最大化布局因此被砸回初始宽度
        if was_current then
          if #S.sessions > 0 then
            local nxt = S.sessions[math.min(cur_idx, #S.sessions)]
            if visible then
              display(nxt.id, pane_focused())
            else
              S.current = nxt.id
            end
          else
            S.current = nil
            if visible then hide_pane() end
          end
        end
        -- agent tab 显示窗同理：先同步挪开死 buffer 再删（sync 不重建、
        -- 不夺焦点）；emit 的事件管线是 schedule 延迟的，赶不上删除时刻
        if alt_viewport and alt_viewport.sync then alt_viewport.sync() end
        -- 此刻死 buffer 已不在任何窗口显示，删除不可能再牵动布局
        if vim.api.nvim_buf_is_valid(args.buf) then
          pcall(vim.api.nvim_buf_delete, args.buf, { force = true })
        end
        emit()
      end)
    end,
  })

  -- opencode 对 SIGHUP 会自我重启，退出 nvim 前必须对进程组发 TERM
  vim.api.nvim_create_autocmd("ExitPre", {
    group = S.augroup,
    callback = function()
      for _, s in ipairs(S.sessions) do
        if s.pid then
          if vim.fn.has("unix") == 1 then
            os.execute("kill -TERM -" .. s.pid .. " 2>/dev/null")
          else
            pcall(vim.uv.kill, s.pid, "SIGTERM")
          end
        end
      end
      -- 状态管线收尾：停监听并删除本实例事件邮箱（docs/adr/0003）
      if status_watcher.handle then
        status_watcher.handle:stop()
        status_watcher.handle:close()
        status_watcher.handle = nil
      end
      if status_watcher.file then
        vim.uv.fs_unlink(status_watcher.file)
        status_watcher.file = nil
      end
    end,
  })
end

function M.toggle()
  if alt_viewport and alt_viewport.active() then return end -- agent tab 内 no-op（ADR 0005）
  if pane_valid() then
    hide_pane()
  elseif #S.sessions == 0 then
    M.new()
  else
    display(S.current, true)
  end
end

function M.new()
  local adapter = adapters[S.ptype]
  if adapter then adapter.new() end
end

function M.cycle(dir)
  if #S.sessions <= 1 then return end
  local idx = by_id(S.current) or 0
  local next_idx = ((idx - 1 + dir) % #S.sessions) + 1
  display(S.sessions[next_idx].id, false)
  if pane_focused() then vim.cmd("stopinsert") end
end

function M.focus()
  display(S.current, true)
end

function M.show_only()
  -- ensure_visible 在 agent tab 内 = 右窗就位（claudecode provider 调用路径）
  if alt_viewport and alt_viewport.active() then
    alt_viewport.show(S.current, false)
  else
    show_pane()
  end
end

function M.hide()
  hide_pane()
end

-- pick_win 显式选中 pane 后由 snacks 包装 action 调用：放行下一个进入 pane 的 buffer
function M.arm_override()
  S.override_once = true
end

function M.send(text, submit)
  if #S.sessions == 0 then
    M.new()
  end
  local _, cur = by_id(S.current)
  if not cur then return end
  local chan = vim.b[cur.bufnr].terminal_job_id
  if chan then
    vim.api.nvim_chan_send(chan, submit == false and text or (text .. "\n"))
  end
  vim.schedule(function() M.focus() end)
end

function M.delete(id)
  local _, sess = by_id(id)
  if not sess then return end
  if sess.job_id then vim.fn.jobstop(sess.job_id) end
  -- TermClose 回调负责移除和清理
end

-- statusline 段：每 session「图标 + 随行空格」等距排布；图标 = 状态表情 ×
-- 当前(实心)/后台(空心)孪生，与颜色双编码状态。空格承接 PUA 大字形向右
-- 溢出（Ghostty kitty 式"PUA+尾随空白"渲染）。pane 收起时全体换 robot_off
-- 睡觉（此时"当前"标记暂不可见，重开即恢复，状态色保留）。docs/adr/0003
function M.status()
  if #S.sessions == 0 then return "" end
  -- agent tab 内不显示本段：树已承载全部信息（用户裁决，ADR 0005）
  if alt_viewport and alt_viewport.active() then return "" end
  -- 睡觉 = 当前视角看不到但仍存在：pane_valid 本就是同 tab 判定，
  -- 人在哪个 tab 就看那个 tab 的 pane；agent tab 存在 ≠ 看得到（ADR 0003 修订）
  local hidden = not pane_valid()
  local parts = {}
  for i, s in ipairs(S.sessions) do
    local glyph, hl = M.icon_for(s.state, s.id == S.current)
    if hidden then glyph = ROBOT_OFF end
    parts[i] = "%#" .. hl .. "#" .. glyph .. " "
  end
  return table.concat(parts) .. "%*"
end

-- 图标计算（statusline / agent tab 树共用同一隐喻，docs/adr/0003/0005）：
-- 表情×实心/空心孪生 + 状态色，返回 glyph, highlight
function M.icon_for(state, is_current)
  local pair = STATE_ICON[state] or NEUTRAL_ICON
  return pair[is_current and 1 or 2], STATE_HL[state] or HL_NEUTRAL
end

-- 视口快照（agent tab 树渲染用）：存活序即词汇表的位置编号 #n
function M.list()
  local out = {}
  for i, s in ipairs(S.sessions) do
    out[i] = { id = s.id, state = s.state, current = s.id == S.current, pos = i }
  end
  return out
end

function M.current_id()
  return S.current
end

function M.buf_of(id)
  local _, s = by_id(id)
  return s and s.bufnr or nil
end

-- 选中并显示（agent tab 树 <CR> 路径；focus=焦点进显示窗）
function M.select(id, focus)
  display(id, focus)
end

-- 备用视口注册（agent_tab.setup 调用；vp = { active = fn, show = fn }）
function M.set_alt_viewport(vp)
  alt_viewport = vp
end

-- 本实例的状态事件邮箱路径（测试/诊断用）
function M.event_file()
  return status_watcher.file or status_file()
end

function M.count()
  return #S.sessions
end

function M.pane_visible()
  return pane_valid()
end

function M.current_buf()
  local _, cur = by_id(S.current)
  return cur and cur.bufnr or nil
end

function M.picker()
  -- agent tab 内改道：列表形态 = 左侧树而非浮窗（aa 的隐喻是"看 agent
  -- 列表"，形态随视口），树 toggle 由 agent_tab 提供（ADR 0005）
  if alt_viewport and alt_viewport.active() and alt_viewport.picker then
    return alt_viewport.picker()
  end
  local items = { { text = "+ new session", is_new = true } }
  for i, s in ipairs(S.sessions) do
    table.insert(items, { text = string.format("%s #%d", PTYPE_ICON, i), id = s.id, bufnr = s.bufnr })
  end

  Snacks.picker({
    title = "Agent sessions (" .. S.ptype .. ")",
    items = items,
    format = function(item)
      return { { item.text } }
    end,
    preview = function(ctx)
      local item = ctx.item
      if not item or item.is_new or not item.bufnr then return true end
      local ok, lines = pcall(vim.api.nvim_buf_get_lines, item.bufnr, -101, -1, false)
      if ok and lines then ctx.preview:set_lines(lines) end
      return true
    end,
    confirm = function(picker, item)
      picker:close(function()
        if item.is_new then
          M.new()
        else
          display(item.id, true)
        end
      end)
    end,
    actions = {
      agent_delete = function(picker, item)
        picker:close(function()
          if not item.is_new and item.id then M.delete(item.id) end
        end)
      end,
    },
    win = {
      input = {
        keys = {
          ["d"] = { "agent_delete", mode = { "n" } },
        },
      },
    },
  })
end

return M
