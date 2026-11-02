local lazy = vim.fn.stdpath("data") .. "/lazy"
package.path = REPO .. "/lua/?.lua;" .. package.path
for _, plugin in ipairs({ "neo-tree.nvim", "nui.nvim", "plenary.nvim" }) do
  package.path = lazy .. "/" .. plugin .. "/lua/?.lua;"
    .. lazy .. "/" .. plugin .. "/lua/?/init.lua;" .. package.path
end
require("neo-tree").setup({ sources = { "agent_tree" }, default_source = "agent_tree" })
vim.g.ai_assistant = "codex"
local fake = vim.fn.tempname() .. "-codex"
vim.fn.writefile({
  "#!/bin/sh",
  "stty -echo",
  "printf 'Codex (fake)\\n› \\n'",
  "while IFS= read -r line; do",
  '  case "$line" in',
  '    "/rename "*) printf "\\033]0;%s\\007" "${line#/rename }" ;;',
  '    /other) printf "\\033]7;file://localhost/tmp\\007" ;;',
  '  esac',
  "done",
}, fake)
vim.fn.setfperm(fake, "rwxr-xr-x")
vim.env.AGENT_CODEX_BIN = fake
dofile(REPO .. "/lua/config/keymaps.lua")
local A = require("agent_sessions")
local T = require("agent_tab")
local lib = dofile(REPO .. "/scripts/testlib.lua")
local check = lib.check
vim.o.columns, vim.o.lines = 200, 50
A.new(nil, false)
A.new(nil, false)
local first, second = A.list()[1].id, A.list()[2].id
T.toggle()
lib.quiesce()
local function tree_name(id)
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(T.tab())) do
    if vim.w[w].agent_tree then
      local state = require("neo-tree.sources.manager").get_state("agent_tree", T.tab(), w)
      local node = state.tree and state.tree:get_node("session:" .. id)
      return node and node.name
    end
  end
end
-- 同实际 /rename 一样通过 PTY 发出 OSC 0 元数据，不直接改模块状态。
A.command(first, "/rename 后台新名字")
check("/rename 后后台 session 名字回流", vim.wait(2000, function()
  return A.list()[1].name == "后台新名字"
end))
check("真实 agent tree 自动刷新", vim.wait(2000, function()
  return tree_name(first) == "后台新名字"
end))
check("不误改当前 session", A.list()[2].name == nil and A.current_id() == second)
A.command(first, "/rename 再次改名")
check("连续改名覆盖旧树名", vim.wait(2000, function()
  return tree_name(first) == "再次改名"
end))
A.command(first, "/other")
lib.quiesce(500)
check("其他 OSC 不改名", A.list()[1].name == "再次改名")
A.delete(first, true)
A.delete(second, true)
vim.wait(2000, function() return A.count() == 0 end)
vim.fn.delete(fake)
lib.finish()
