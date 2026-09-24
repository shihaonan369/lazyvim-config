-- agent_sessions: 多 agent session 管理（设计见 docs/adr/0001）
-- 单一 agent pane（右侧 30%），session = 后台存活的 terminal buffer。
local M = {}

local PANE_WIDTH = 0.30

-- 与 <leader>a 分组同款图标（lua/plugins/which-key.lua 定义，U+EE0D）
local PTYPE_ICON = vim.fn.nr2char(0xEE0D)

local S = {
  ptype = nil,      -- "claude" | "codex" | "opencode"
  sessions = {},    -- { { id, bufnr, job_id, pid } }
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
    vim.api.nvim_win_close(S.pane_win, false)
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
local function is_territory(win)
  return vim.w[win].agent_pane == true or vim.w[win].shell_term == true
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
    if vim.api.nvim_win_get_width(pane) >= vim.o.columns - 2 then
      vim.cmd("aboveleft split") -- 底部 shell 全宽：主区开在上方
    else
      vim.cmd("leftabove vsplit") -- agent pane 右侧：主区开在左方，保住 pane 居右
    end
    win = vim.api.nvim_get_current_win()
  end)
  if vim.w[pane].agent_pane then
    vim.api.nvim_win_set_width(pane, math.floor(vim.o.columns * PANE_WIDTH))
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
          if not is_agent_buf(buf) then
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

local function display(id, focus)
  S.current = id
  show_pane()
  if focus then
    vim.api.nvim_set_current_win(S.pane_win)
    vim.cmd("startinsert")
  end
  emit()
end

local function spawn(cmd_list, env)
  local sess = { id = S.next_id, bufnr = nil, job_id = nil, pid = nil }
  S.next_id = S.next_id + 1

  local prev_win = vim.api.nvim_get_current_win()
  -- pane 先立起来：termopen 需要一个当前 buffer，session 建好即显示
  sess.bufnr = vim.api.nvim_create_buf(false, true)
  vim.b[sess.bufnr].agent_session = true -- buffer 身份标记：pane 不变量只认它（docs/adr/0002）
  table.insert(S.sessions, sess) -- TermOpen 回调依赖 registry 已登记
  show_pane()
  vim.api.nvim_win_set_buf(S.pane_win, sess.bufnr)
  S.current = sess.id

  local opts = { cwd = vim.fn.getcwd() }
  if env and next(env) ~= nil then opts.env = env end
  -- termopen 挂在当前 buffer 上：pane 复用（未走 vsplit）时焦点可能在主区，
  -- 必须临时切到 pane 执行，否则会劫持主区当前 buffer
  vim.api.nvim_win_call(S.pane_win, function()
    sess.job_id = vim.fn.termopen(cmd_list, opts)
  end)
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

-- 沙箱环境（IS_SANDBOX=1）下 claude 才以 bypassPermissions 启动
-- （新版写法，替代 --dangerously-skip-permissions）
local function claude_spawn_cmd(cmd_list)
  if vim.env.IS_SANDBOX ~= "1" then return cmd_list end
  for _, arg in ipairs(cmd_list) do
    if arg == "--permission-mode" then return cmd_list end
  end
  return vim.list_extend(vim.deepcopy(cmd_list), { "--permission-mode", "bypassPermissions" })
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
        if vim.api.nvim_buf_is_valid(args.buf) then
          pcall(vim.api.nvim_buf_delete, args.buf, { force = true })
        end
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
    end,
  })
end

function M.toggle()
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
  show_pane()
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

function M.status()
  local idx = by_id(S.current)
  if not idx then return "" end
  return string.format("%s #%d/%d", PTYPE_ICON, idx, #S.sessions)
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
