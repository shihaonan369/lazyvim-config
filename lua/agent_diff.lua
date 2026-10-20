-- agent_diff: claude 改动的「先落后审 + 一键回滚」（ADR 0007 层 2）。
-- 快照由 scripts/agent-diff-hook.sh 在 PostToolUse 落盘：该文件本回合首次
-- 编辑前的 originalFile = 回合基线（2026-10-20 实证 hook JSON 带
-- tool_response.originalFile）。目录 stdpath("run")/agent-diff/
-- <getpid()>.<session id><文件绝对路径镜像>，tag 前缀与状态归因同构。
-- 零轮询：只在用户按键时扫描存活 session 的快照集（已退 session 的快照
-- 不再列出，随 nvim 退出由 ExitPre 清）。accept = 删快照（改动留盘）；
-- deny = 基线字节级写回（fs_copyfile）+ checktime。
local sessions = require("agent_sessions")
local M = {}

local ROOT = vim.fn.stdpath("run") .. "/agent-diff"

local function tag_of(id)
  return vim.fn.getpid() .. "." .. id
end

-- 存活 session 的待审改动集合：{ { file, snap, sid, pos, name } }
function M.changed()
  local out = {}
  for _, s in ipairs(sessions.list()) do
    local dir = ROOT .. "/" .. tag_of(s.id)
    if vim.fn.isdirectory(dir) == 1 then
      local stack = { dir }
      while #stack > 0 do
        local d = table.remove(stack)
        for name, type in vim.fs.dir(d) do
          local p = d .. "/" .. name
          if type == "directory" then
            stack[#stack + 1] = p
          else
            out[#out + 1] =
              { file = p:sub(#dir + 1), snap = p, sid = s.id, pos = s.pos, name = s.name }
          end
        end
      end
    end
  end
  return out
end

local reviews = {} -- file -> { snapbuf, fwin, rtab, from_tab }（在审视图）
local last_file = nil

local function find_item(file)
  for _, it in ipairs(M.changed()) do
    if it.file == file then return it end
  end
end

local function close_review(file)
  local r = reviews[file]
  if not r then return end
  reviews[file] = nil
  -- 人还在审查 tab 时先回来源 tab（否则交给 nvim 默认跳转）
  if
    r.from_tab
    and vim.api.nvim_tabpage_is_valid(r.from_tab)
    and vim.api.nvim_get_current_tabpage() == r.rtab
  then
    pcall(vim.api.nvim_set_current_tabpage, r.from_tab)
  end
  if vim.api.nvim_win_is_valid(r.fwin) then
    pcall(vim.api.nvim_win_close, r.fwin, true)
  end
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(w) and vim.api.nvim_win_get_buf(w) == r.snapbuf then
      pcall(vim.api.nvim_win_close, w, true)
    end
  end
  -- 两窗皆闭 → 审查 tab 自灭；若因故残留（用户在审查 tab 里又开了窗），留给用户
  if vim.api.nvim_buf_is_valid(r.snapbuf) then
    pcall(vim.api.nvim_buf_delete, r.snapbuf, { force = true })
  end
end

-- 审查视图开专属 tab（$tabnew 建于末尾，g1-g9 零扰动——agent tab 同款惯例，
-- ADR 0005）：equalalways 只在 tabpage 内重排，当前 tabpage 的 pane 几何
-- 零扰动（几何只属于用户，ADR 0002）。tab 内一对窗：左 = 快照基线
-- （scratch），右 = 盘上现况。
function M.review(file)
  local item = find_item(file)
  if not item then
    vim.notify("agent_diff: 无该文件的待审快照", vim.log.levels.WARN)
    return
  end
  close_review(file) -- 重复审查：先撤旧视图，避免 buffer 重名 E95
  local snapbuf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(snapbuf, 0, -1, false, vim.fn.readfile(item.snap))
  vim.bo[snapbuf].buftype = "nofile"
  vim.bo[snapbuf].modifiable = false
  vim.api.nvim_buf_set_name(snapbuf, "agent-diff://" .. file)
  local from_tab = vim.api.nvim_get_current_tabpage()
  vim.cmd("$tabnew")
  local rtab = vim.api.nvim_get_current_tabpage()
  local fwin = vim.api.nvim_get_current_win()
  vim.cmd("edit " .. vim.fn.fnameescape(file))
  vim.cmd("vsplit")
  local swin = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(swin, snapbuf)
  vim.cmd("diffthis")
  vim.api.nvim_win_call(fwin, function() vim.cmd("diffthis") end)
  reviews[file] = { snapbuf = snapbuf, fwin = fwin, rtab = rtab, from_tab = from_tab }
  last_file = file
end

function M.review_picker()
  local items = M.changed()
  if #items == 0 then
    vim.notify("agent_diff: 无待审改动")
    return
  end
  vim.ui.select(items, {
    prompt = "审查 agent 改动（ada=接受 / add=回滚基线）",
    format_item = function(it)
      return it.file .. "  ·  #" .. it.pos .. (it.name and (" " .. it.name) or "")
    end,
  }, function(choice)
    if choice then M.review(choice.file) end
  end)
end

function M.accept()
  if not last_file then
    vim.notify("agent_diff: 无在审项（先 <leader>ad 审查）", vim.log.levels.WARN)
    return
  end
  local item = find_item(last_file)
  if not item then
    vim.notify("agent_diff: 快照已不在（已处理？）", vim.log.levels.WARN)
    close_review(last_file)
    last_file = nil
    return
  end
  vim.fn.delete(item.snap)
  close_review(last_file)
  vim.notify("已接受（改动留盘）：" .. last_file)
  last_file = nil
end

function M.deny()
  if not last_file then
    vim.notify("agent_diff: 无在审项（先 <leader>ad 审查）", vim.log.levels.WARN)
    return
  end
  local item = find_item(last_file)
  if not item then
    vim.notify("agent_diff: 快照已不在（已处理？）", vim.log.levels.WARN)
    close_review(last_file)
    last_file = nil
    return
  end
  local file, snap = item.file, item.snap
  vim.uv.fs_copyfile(snap, file, function(err)
    if err then
      vim.notify("agent_diff: 基线写回失败 " .. tostring(err), vim.log.levels.ERROR)
      return
    end
    vim.schedule(function()
      -- buffer 名可能经符号链接解析（如 macOS /var→/private/var），resolve 对齐
      local want = vim.fn.resolve(file)
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(b) and vim.fn.resolve(vim.api.nvim_buf_get_name(b)) == want then
          pcall(vim.api.nvim_buf_call, b, function() vim.cmd("checktime") end)
        end
      end
      vim.fn.delete(snap)
      close_review(file)
      vim.notify("已回滚到回合基线：" .. file)
      if last_file == file then last_file = nil end
    end)
  end)
end

function M.setup()
  local gid = vim.api.nvim_create_augroup("AgentDiff", { clear = true })
  -- 收尾（仿状态邮箱的 ExitPre 范式）：清本实例全部 tag 目录，孤儿不留。
  -- 先收集再删——不边遍历边删
  vim.api.nvim_create_autocmd("ExitPre", {
    group = gid,
    callback = function()
      if vim.fn.isdirectory(ROOT) ~= 1 then return end
      local prefix = tostring(vim.fn.getpid()) .. "."
      local doomed = {}
      for name, _ in vim.fs.dir(ROOT) do
        if name:sub(1, #prefix) == prefix then doomed[#doomed + 1] = name end
      end
      for _, name in ipairs(doomed) do
        vim.fn.delete(ROOT .. "/" .. name, "rf")
      end
    end,
  })
end

return M
