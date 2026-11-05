-- Skill regression: real aspawn → plugin spawn → fake Claude PTY + transcript.
-- Fake TUI renders ❯ before consuming input, dropping early injected /rename.
-- Like Claude 2.1.317, transcript birth waits for the first submission.
package.path = REPO .. '/lua/?.lua;' .. package.path
vim.g.ai_assistant = 'claude'
vim.g.claude_backend = 'native'
local lib = dofile(REPO .. '/scripts/testlib.lua')
local check = lib.check
local dir = vim.fn.tempname()
vim.fn.mkdir(dir, 'p')
local fake = dir .. '/claude'
vim.fn.writefile({
  '#!/usr/bin/env python3',
  'import json, os, pathlib, select, sys, termios, time, tty',
  'tty.setraw(0)',
  'args = sys.argv[1:]',
  'sid = args[args.index("--session-id") + 1] if "--session-id" in args else "unnamed"',
  'name = args[args.index("--name") + 1] if "--name" in args else None',
  'root = pathlib.Path(__file__).parent',
  '(root / (sid + ".args")).write_text(json.dumps(args))',
  'transcript = root / (sid + ".jsonl")',
  'with open(os.environ["AGENT_STATUS_FILE"], "a") as f:',
  [[    f.write(json.dumps(dict(tag=os.environ["AGENT_SESSION_TAG"], sid=sid, transcript=str(transcript))) + "\n")]],
  'time.sleep(0.2)',
  [[os.write(1, "Claude fake\r\n❯ \r\n".encode())]],
  'time.sleep(1.0)',
  '# Input sent before the consumer starts is silently lost.',
  'while select.select([0], [], [], 0)[0]: os.read(0, 65536)',
  'received = b""',
  'while True:',
  '    data = os.read(0, 65536)',
  '    if not data: break',
  '    received += data',
  '    with (root / (sid + ".input")).open("ab") as f: f.write(data)',
  '# Real Claude lazily creates the transcript on first submission.',
  [[    if b"\r" in received and not transcript.exists():]],
  '        with transcript.open("w") as f:',
  [[            f.write(json.dumps(dict(type="system")) + "\n")]],
  [[            if name: f.write(json.dumps({"type":"custom-title", "customTitle":name}) + "\n")]],
}, fake)
vim.fn.setfperm(fake, 'rwxr-xr-x')
vim.env.PATH = dir .. ':' .. vim.env.PATH
vim.env.AGENT_CLAUDE_BIN = fake
local A = require('agent_sessions')
A.setup()
dofile(REPO .. '/skills/agent-sessions/scripts/asend.lua')
local sent = {}
local orig_send = vim.api.nvim_chan_send
vim.api.nvim_chan_send = function(ch, value)
  sent[#sent + 1] = value
  return orig_send(ch, value)
end
local function name_of(id)
  for _, s in ipairs(A.list()) do if s.id == id then return s.name end end
end
local function args_for_last()
  local files = vim.fn.glob(dir .. '/*.args', false, true)
  table.sort(files, function(a, b) return vim.fn.getftime(a) > vim.fn.getftime(b) end)
  return #files > 0 and vim.json.decode(table.concat(vim.fn.readfile(files[1]), '\n')) or {}
end
vim.cmd('wincmd h')
local win = vim.api.nvim_get_current_win()
local name = [[REPRO-测试名 with "quotes" 'single' $HOME; $(echo unsafe)]]
local id = _G.aspawn(name)
check('spawn keeps focus', vim.api.nvim_get_current_win() == win)
check('name is not fabricated before Claude reply', name_of(id) == nil)
local pf = dir .. '/prompt.md'
vim.fn.writefile({ 'first prompt', 'second line' }, pf)
check('prompt queued', _G.aprompt_file(id, pf) == 'ok')
check('spawn name survives early-input loss via transcript', vim.wait(5000, function()
  return name_of(id) == name
end))
local args = args_for_last()
local ni
for i, arg in ipairs(args) do if arg == '--name' then ni = i end end
check('name is one exact argv including spaces/metacharacters', ni ~= nil and args[ni + 1] == name)
check('no automatic /rename PTY injection', (function()
  for _, value in ipairs(sent) do if value:find('/rename', 1, true) then return false end end
  return true
end)())
local function input_has_prompt()
  for _, path in ipairs(vim.fn.glob(dir .. '/*.input', false, true)) do
    local data = table.concat(vim.fn.readfile(path, 'b'), '\n')
    if data:find('\27[200~first prompt\nsecond line\27[201~', 1, true)
      and data:find('\13', 1, true) then return true end
  end
  return false
end
check('first prompt + delayed CR survive startup', vim.wait(4000, input_has_prompt))
-- The plugin remembers the executable. It must remain usable without skill args.
local count = #vim.fn.glob(dir .. '/*.args', false, true)
A.new(nil, false)
check('later ordinary spawn works without inheriting name', vim.wait(3000, function()
  local path = dir .. '/unnamed.args'
  if vim.fn.filereadable(path) == 0 then return false end
  local argv = vim.json.decode(table.concat(vim.fn.readfile(path), '\n'))
  return not vim.tbl_contains(argv, '--name')
    and #vim.fn.glob(dir .. '/*.args', false, true) > count
end))
local ids = {}
for _, s in ipairs(A.list()) do ids[#ids + 1] = s.id end
for _, sid in ipairs(ids) do A.delete(sid, true) end
vim.wait(2000, function() return A.count() == 0 end)
vim.api.nvim_chan_send = orig_send
vim.fn.delete(dir, 'rf')
lib.finish()
