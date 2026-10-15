-- agent_tree: neo-tree 外部源——agent tab 左侧的 session 列表（docs/adr/0005）
-- 挂接：sources 里放本模块名（外部源契约见 neo-tree setup/init.lua：模块提供
-- name/display_name/components/commands/navigate，配置吃 default_config）。
-- 刷新由 agent_tab 经 User AgentSessionsChanged → manager.refresh 驱动，
-- 与状态管线同源（docs/adr/0003），零轮询。
-- 外观：状态机器人图标在每项前方（表情×实心/空心孪生 + 状态色，与
-- statusline/picker 同一隐喻）；顺序恒为存活序——切换不重排，当前项只靠
-- 实心图标 + 高亮标识（用户裁决 2026-10-15；词汇表：session 用位置编号
-- #n 称呼，顺序稳定编号才稳定）。
local manager = require("neo-tree.sources.manager")
local renderer = require("neo-tree.ui.renderer")
local agent = require("agent_sessions")

local M = {
  name = "agent_tree",
  display_name = " 󰚩 Agents ",
}

M.default_config = {
  window = {
    mappings = {
      ["<cr>"] = "agent_open",
      ["<2-LeftMouse>"] = "agent_open",
      ["a"] = "agent_new",
      ["d"] = "agent_delete",
      ["r"] = "agent_rename", -- 重命名（claude 双向同步；codex/opencode 暂本地，TODO）
      -- q 必须接管：neo-tree 自带 close_window 在 position=current 窗口里
      -- 只清 buffer 不关窗，留下空 editor 窗且 agent_tree winvar 还挂着，
      -- ensure_tree 误判树在、永远不重建（实测踩过）；再开走 <leader>aa
      ["q"] = "agent_close_tree",
    },
  },
  renderers = {
    agent_session = {
      { "icon", padding_right = 1 },
      { "label" },
    },
    agent_action = {
      { "label" },
    },
  },
}

-- 外部源的 components 不与 common 自动合并（内置源也是显式引入再扩展），
-- 缺 indent 会整树渲染告警——这里带上全套 common 再覆盖自定义项
local common_components = require("neo-tree.sources.common.components")

M.components = vim.tbl_extend("force", common_components, {
  icon = function(_, node)
    local e = node.extra or {}
    if e.kind ~= "session" then return {} end
    local glyph, hl = agent.icon_for(e.state, e.current)
    return { text = glyph .. " ", highlight = hl } -- 随行空格承接 PUA 溢出（ADR 0003）
  end,
  label = function(_, node)
    local e = node.extra or {}
    return {
      text = node.name,
      highlight = e.current and "NeoTreeFileNameOpened" or nil,
    }
  end,
})

-- 命令集：自定义三个 + 从 common 精选的普适命令（show_help/close_window/
-- cancel）。不做全量 common 扩展——那会让 rename/trash 等文件命令在本源
-- "合法"，按错不告警反而更糟；其余默认映射在 spec 层逐个 "none"
local common_commands = require("neo-tree.sources.common.commands")

M.commands = vim.tbl_extend("keep", {
  agent_open = function(state)
    local node = state.tree:get_node()
    if not node then return end
    local e = node.extra or {}
    if e.id then
      agent.select(e.id, true) -- 切换 + 焦点右移（对齐 neo-tree open 惯例）
    end
  end,
  agent_new = function()
    agent.new()
  end,
  agent_delete = function(state)
    local node = state.tree:get_node()
    local e = node and node.extra or {}
    if e.kind ~= "session" then return end
    local n = e.pos or "?"
    if vim.fn.confirm("删除 agent session #" .. n .. "?", "&Yes\n&No") ~= 1 then return end
    agent.delete(e.id) -- 移除与清理走 TermClose 既有管线
  end,
  agent_rename = function(state)
    local node = state.tree:get_node()
    local e = node and node.extra or {}
    if e.kind ~= "session" then return end
    local cur_name
    for _, it in ipairs(agent.list()) do
      if it.id == e.id then cur_name = it.name end
    end
    vim.ui.input({
      prompt = "Rename agent session #" .. (e.pos or "?") .. ": ",
      default = cur_name or "",
    }, function(input)
      if input and input ~= "" then agent.rename(e.id, input) end
    end)
  end,
  refresh = function()
    M.refresh()
  end,
  agent_close_tree = function()
    pcall(vim.api.nvim_win_close, 0, false) -- 树是 tab 唯一窗时关窗即关 tab，幂等可重建
  end,
}, {
  show_help = common_commands.show_help,
  cancel = common_commands.cancel,
})

-- 外部源契约必备（manager.validate_source 强制要求 setup/navigate 均为函数）；
-- 本源无全局事件要订阅，空实现即可
M.setup = function(_config, _global_config) end

M.navigate = function(state)
  state.path = state.path or "agents"
  -- 只列 session：新建走 a 键，不设 "+ new agent" 行；顺序恒为存活序，
  -- 切换 current 不重排（重排会让位置编号 #n 漂移，肌肉记忆无处安放）
  local items = {}
  for _, s in ipairs(agent.list()) do
    items[#items + 1] = {
      id = "session:" .. s.id,
      name = s.name or ("#" .. s.pos), -- 名字优先，无名回退位置编号（词汇表）
      type = "agent_session",
      extra = { kind = "session", id = s.id, pos = s.pos, state = s.state, current = s.current, name = s.name },
    }
  end
  renderer.show_nodes(items, state)
end

M.refresh = function()
  manager.refresh(M.name)
end

return M
