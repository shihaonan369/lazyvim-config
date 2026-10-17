-- agent_sessions 远程驱动 API（skill: agent-sessions）
-- 由 nvim --server "$NVIM" --remote-expr 的 luaeval dofile 加载，全部挂 _G、
-- 幂等可重复加载。转义铁律：一切 \r/\21/\27 序列只允许出现在本文件里，
-- 调用侧 remote-expr 一律传裸字符串（[[...]] 或文件路径），杜绝 bash→vim
-- 双层转义把控制字符半路展开（2026-10-17 实证：内联 \r 会炸 E5107、\21 被
-- vim 吞掉变字面量）。
local ok, AS = pcall(require, 'agent_sessions')
if not ok then error('agent_sessions 模块未加载（不在 nvim agent 环境内）') end

local function chan_of(id)
  local b = AS.buf_of(id)
  if not b then return nil end
  local ch = vim.b[b].terminal_job_id
  if not ch then return nil end
  return ch, b
end

local function send(ch, s) pcall(vim.api.nvim_chan_send, ch, s) end

-- 建新 claude 会话（--session-id 携额外参数才触发 claude_open 的 wants_new
-- 分支走 spawn；focus=false 不抢用户焦点）。带名：经 claude_open 第 4 参入
-- nvim 侧就绪队列，TUI 就绪后自动 /rename（name 为 nil 则匿名）。返回新会话
-- id——命令即回，命名异步送达（回流滞后见 SKILL.md）。
_G.aspawn = function(name)
  local f = io.open('/proc/sys/kernel/random/uuid', 'r')
  local uuid = f:read('*l')
  f:close()
  AS.claude_open('claude --session-id ' .. uuid, {}, false, name)
  return AS.current_id()
end

-- TUI 就绪判定：输入框 ❯ 渲染出来即能收按键。
_G.aready = function(id)
  local _, b = chan_of(id)
  if not b then return 'nobuf' end
  for _, x in ipairs(vim.api.nvim_buf_get_lines(b, 0, -1, false)) do
    if x:find('❯', 1, true) then return 'ready' end
  end
  return 'wait'
end

-- 会话命名（/rename 注入，claude 侧 custom-title.json 即落；nvim 树回流有
-- 滞后）。注入本体在 AS.rename（文字与 CR 分包延时），此处只做入口
_G.arename = function(id, name)
  AS.rename(id, name)
  return 'ok'
end

-- 首发 prompt：AS.when_ready 入队（就绪即投喂；与改名同队 FIFO 串行）。
-- 投喂 = Ctrl-U 清草稿 → 括号粘贴（多行安全）→ 延时 CR 提交。文字与 CR
-- 必须分开发（TUI 会吞同包紧跟的 CR）；返回占用时长，队列顺延下一条
_G.aprompt_file = function(id, path)
  AS.when_ready(id, function()
    local ch = chan_of(id)
    if not ch then return end
    local lines = vim.fn.readfile(path)
    send(ch, '\21')
    send(ch, '\27[200~' .. table.concat(lines, '\n') .. '\27[201~')
    vim.defer_fn(function() send(ch, '\13') end, 400)
    return 550 -- 占用至延时 CR 落地（400ms＋余量）
  end)
  return 'ok'
end

_G.adelete = function(id) AS.delete(id); return 'ok' end
_G.acount = function() return AS.count() end
_G.acurrent = function() return AS.current_id() end
_G.alist = function() return vim.inspect(AS.list()) end

-- 调试：buffer 尾部非空行 dump
_G.abuf = function(id, n)
  local _, b = chan_of(id)
  if not b then return 'nobuf' end
  local t = vim.api.nvim_buf_get_lines(b, 0, -1, false)
  local out = {}
  for i = math.max(1, #t - (n or 8)) + 1, #t do
    if t[i] ~= '' then out[#out + 1] = i .. ':[' .. t[i]:sub(1, 120) .. ']' end
  end
  return table.concat(out, ' ')
end
