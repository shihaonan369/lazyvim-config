-- Run: NVIM_LOG_FILE=/tmp/nvim-osc52.log nvim --headless --clean -i NONE -l scripts/test-agent-osc52.lua
local root = vim.fn.getcwd()
package.path = root .. '/lua/?.lua;' .. package.path
local fake = vim.fn.tempname()
local copied
vim.g.clipboard = {
  name = 'OSC52 test',
  copy = { ['+'] = function(lines) copied = table.concat(lines, '\n') end, ['*'] = function() end },
  paste = { ['+'] = function() return {} end, ['*'] = function() return {} end },
}
-- Match Codex's var_os("TMUX").is_some(): empty still means present.
vim.fn.writefile({ '#!/bin/sh',
  'stty -echo',
  'if test "${TMUX+x}" = x; then',
  [[  printf '\033Ptmux;\033\033]52;c;SGVsbG8=\007\033\\']],
  'else', [[  printf '\033]52;c;SGVsbG8=\007']], 'fi', 'exec cat',
}, fake)
vim.fn.setfperm(fake, 'rwxr-xr-x')
vim.env.AGENT_CODEX_BIN = fake
vim.env.TMUX = '/tmp/fake,1234,0'
vim.env.TMUX_PANE = '%5'
vim.g.ai_assistant = 'codex'
local A = require('agent_sessions')
A.setup()
A.new()
vim.wait(1500, function() return copied ~= nil end)
local text = table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_get_current_buf(), 0, -1, false), '\n')
local ok = copied == 'Hello' and not text:find('52;c;', 1, true)
A.delete(A.current_id(), true)
vim.fn.delete(fake)
print(ok and 'PASS: OSC52 copied Hello without leaking payload' or ('FAIL: copied=' .. tostring(copied) .. ' terminal=' .. text))
vim.cmd(ok and 'qa!' or 'cquit 1')
