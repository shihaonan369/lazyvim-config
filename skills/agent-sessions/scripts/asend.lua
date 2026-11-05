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

-- 建新 Claude：--name 启动定名，避开 ❯ 已渲染但输入循环未启动时吞掉
-- /rename 的窗口。claude_open 按空白拆命令，helper 用 base64 保住含空格/
-- 引号的名字（不是 shell 转义）；第 4 参留空，绝不再排自动改名。
-- focus=false 不抢焦点，名字仍由 Claude transcript 回流，不伪造本地成功。
local script_dir = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h')
-- UUID 取法双平台：/proc 是 Linux 独有（容器 clone 验证环境），Mac 侧
-- io.open 返回 nil 原地炸 E5108——退 luv CSPRNG 自拼 v4（version/variant
-- 位用十进制取模置位，不依赖 bit 库）
local function uuid4()
  local f = io.open('/proc/sys/kernel/random/uuid', 'r')
  if f then
    local u = f:read('*l')
    f:close()
    return u
  end
  local b = { vim.uv.random(16):byte(1, -1) }
  b[7] = b[7] % 16 + 64   -- 0x40..0x4f → version 4
  b[9] = b[9] % 64 + 128  -- 0x80..0xbf → variant 10xx
  local hex = {}
  for i = 1, 16 do hex[i] = string.format('%02x', b[i]) end
  return table.concat(hex, '', 1, 4) .. '-' .. table.concat(hex, '', 5, 6)
    .. '-' .. table.concat(hex, '', 7, 8) .. '-' .. table.concat(hex, '', 9, 10)
    .. '-' .. table.concat(hex, '', 11, 16)
end

_G.aspawn = function(name)
  if vim.g.ai_assistant == 'codex' then
    AS.new(name, false)
  elseif vim.g.ai_assistant == 'pi' then
    -- pi：名字随 -n 落进 pi 本尊（adapters.pi），无需 /rename 注入队列
    AS.new(name, false)
  elseif vim.g.ai_assistant == 'claude' then
    local cmd = script_dir .. '/claude_spawn.sh'
    if name and name ~= '' then
      -- 单行会话名；拒绝 shell command substitution 会裁掉的尾换行。
      assert(not name:find('[\r\n]'), '会话名须为单行')
      cmd = cmd .. ' --skill-name=' .. vim.base64.encode(name)
    end
    AS.claude_open(cmd .. ' --session-id ' .. uuid4(), {}, false)
  else
    error('agent-sessions skill 只支持 claude/codex/pi')
  end
  return AS.current_id()
end

-- 与宿主的首发 prompt 队列共用就绪判据。
_G.aready = function(id)
  if not AS.buf_of(id) then return 'nobuf' end
  return AS.is_ready(id) and 'ready' or 'wait'
end

-- 事后改名；AS.rename 分包注入，Claude transcript 回流才算成功。
-- 此入口会清输入草稿；只在会话空闲且无用户草稿时调用。
_G.arename = function(id, name)
  AS.rename(id, name)
  return 'ok'
end

-- 首发 prompt：AS.when_ready 入队（Claude 首帧后另 settle 再投喂）。
-- 投喂 = Ctrl-U 清草稿 → 括号粘贴（多行安全）→ 延时 CR 提交。文字与 CR
-- 必须分开发（TUI 会吞同包紧跟的 CR）；返回占用时长，队列顺延下一条
_G.aprompt_file = function(id, path)
  AS.when_ready(id, function()
    local function paste()
      local ch = chan_of(id)
      if not ch then return end -- settle 期间退出：不再发往旧 channel
      local lines = vim.fn.readfile(path)
      send(ch, '\21')
      send(ch, '\27[200~' .. table.concat(lines, '\n') .. '\27[201~')
      vim.defer_fn(function() send(ch, '\13') end, 400)
    end
    -- ❯ 首帧不等于输入循环已活；移除 rename 后尤其不能把 prompt 提前。
    local settle = vim.g.ai_assistant == 'claude' and 1200 or 0
    if settle > 0 then vim.defer_fn(paste, settle) else paste() end
    return settle + 550 -- 占用至延时 CR 落地（400ms＋余量）
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
