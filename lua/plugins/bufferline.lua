local function session_for(buf)
  local agent = require("agent_sessions")
  for _, item in ipairs(agent.list()) do
    if agent.buf_of(item.id) == buf then
      return item
    end
  end
end

local function cycle(dir)
  local tab = require("agent_tab")
  if not tab.active() then
    vim.cmd(dir < 0 and "BufferLineCyclePrev" or "BufferLineCycleNext")
    return
  end
  -- 按标签的实际顺序（含手动排序）切换；树有焦点时也锚定全局 current，
  -- 不把 terminal buffer 直接塞进树窗。未渲染的新 session 回退存活序。
  local agent = require("agent_sessions")
  local items, current = {}, nil
  for _, element in ipairs(require("bufferline").get_elements().elements) do
    local item = session_for(element.id)
    if item then
      items[#items + 1] = item
      if item.current then
        current = #items
      end
    end
  end
  if not current or #items ~= agent.count() then
    agent.cycle(dir)
    return
  end
  agent.select(items[((current - 1 + dir) % #items) + 1].id, false)
end

-- 标签操作必须走 session API（单一 current / 全视口同步 / 优雅退出），
-- 普通 buffer 原样委托 LazyVim 的行为，包括 Snacks.bufdelete。
local function route(original, action)
  return function(buf)
    local item = session_for(buf)
    if item then
      return action(item.id)
    end
    if type(original) == "function" then
      return original(buf)
    end
    if type(original) == "string" then
      vim.cmd(original:format(buf))
    end
  end
end

return {
  "akinsho/bufferline.nvim",
  keys = {
    {
      "<S-h>",
      function()
        cycle(-1)
      end,
      desc = "Prev Buffer",
    },
    {
      "<S-l>",
      function()
        cycle(1)
      end,
      desc = "Next Buffer",
    },
  },
  opts = function(_, opts)
    local options = opts.options or {}
    opts.options = options
    options.custom_filter = function(buf)
      return require("agent_tab").buffer_visible(buf)
    end
    local name_formatter = options.name_formatter
    options.name_formatter = function(buf)
      local item = session_for(buf.bufnr)
      if item then
        return item.name or ((vim.g.ai_assistant or "agent") .. " #" .. item.pos)
      end
      if name_formatter then
        return name_formatter(buf)
      end
    end
    options.left_mouse_command = route(options.left_mouse_command or "buffer %d", function(id)
      require("agent_sessions").select(id, true)
    end)
    for _, key in ipairs({ "close_command", "right_mouse_command" }) do
      options[key] = route(options[key] or "bdelete! %d", function(id)
        require("agent_sessions").delete(id)
      end)
    end
    -- 显隐判定交给 config/autocmds.lua（当前域 buffer 数与 tab 数独立计算）：
    -- 单 buffer + 多 tab 也必须保留 tab 标签。
    options.auto_toggle_bufferline = false
    -- 强制使用派生高亮，避免主题预定义实底破坏透明。
    options.themable = false
  end,
}
