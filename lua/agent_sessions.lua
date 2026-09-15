-- agent_sessions: 多 agent session 管理（设计见 docs/adr/0001）
-- 单一 agent pane（右侧 30%），session = 后台存活的 terminal buffer。
local M = {}

local PANE_WIDTH = 0.30

local S = {
  ptype = nil,      -- "claude" | "codex" | "opencode"
  sessions = {},    -- { { id, bufnr, job_id, pid } }
  current = nil,    -- session id
  pane_win = nil,   -- winid
  next_id = 1,
  augroup = nil,
  intent = "show",  -- claude provider 桥接: "show" | "new"
  claude_cache = nil, -- { cmd_list, env }
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

local function label(s)
  return string.format("%s #%d", S.ptype, s.id)
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
  table.insert(S.sessions, sess) -- TermOpen 回调依赖 registry 已登记
  show_pane()
  vim.api.nvim_win_set_buf(S.pane_win, sess.bufnr)
  S.current = sess.id

  local opts = { cwd = vim.fn.getcwd() }
  if env and next(env) ~= nil then opts.env = env end
  sess.job_id = vim.fn.termopen(cmd_list, opts)
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
      local sess = spawn(base, S.claude_cache.env)
      display(sess.id, true)
    else
      -- provider 从未被调过，让插件自己构造 cmd/env 走一次 provider.open
      S.intent = "new"
      vim.cmd("ClaudeCode")
    end
  end,
}

-- CLAUDE_CODE_NO_FLICKER=1 让 claude 以 fullscreen TUI（alternate screen）渲染；
-- 仅作用于本系统 spawn 的进程，不影响终端里直接跑的 claude
local function claude_spawn_env(env)
  return vim.tbl_extend("force", env or {}, { CLAUDE_CODE_NO_FLICKER = "1" })
end

-- claude provider 桥接入口（由 claudecode.lua 的 provider table 调用）
function M.claude_open(cmd_string, env, focus)
  local cmd_list = vim.split(cmd_string, "%s+")
  env = claude_spawn_env(env)
  S.claude_cache = { cmd_list = cmd_list, env = env }
  local wants_new = S.intent == "new" or #cmd_list > 1
  S.intent = "show"
  if wants_new or #S.sessions == 0 then
    local sess = spawn(cmd_list, env)
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
    local sess = spawn(cmd_list, env)
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
  local _, cur = by_id(S.current)
  if not cur then return "" end
  return string.format("%s #%d/%d", S.ptype, cur.id, #S.sessions)
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
  for _, s in ipairs(S.sessions) do
    table.insert(items, { text = label(s), id = s.id, bufnr = s.bufnr })
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
