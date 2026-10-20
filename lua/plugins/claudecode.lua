local agent = require("agent_sessions")

-- claudecode.nvim 自定义 terminal provider：终端创建/显示全部交给 agent_sessions
local provider = {
  is_available = function() return true end,
  setup = function(_term_config) agent.setup() end,
  open = function(cmd_string, env, _cfg, focus)
    agent.claude_open(cmd_string, env, focus ~= false)
  end,
  close = function() agent.hide() end,
  simple_toggle = function(cmd_string, env, _cfg)
    agent.claude_toggle(cmd_string, env, false)
  end,
  focus_toggle = function(cmd_string, env, _cfg)
    agent.claude_toggle(cmd_string, env, true)
  end,
  get_active_bufnr = function() return agent.current_buf() end,
  ensure_visible = function() agent.show_only() end,
}

local function send_and_focus(cmd)
  vim.cmd(cmd)
  vim.schedule(function()
    agent.focus()
  end)
end

local function send_range_and_focus()
  local line1 = vim.fn.line("'<")
  local line2 = vim.fn.line("'>")
  if line1 > 0 and line2 > 0 then
    send_and_focus(line1 .. "," .. line2 .. "ClaudeCodeSend")
  end
end

return {
  "coder/claudecode.nvim",
  enabled = function()
    -- 磨合期回退后端（ADR 0007）：默认 native（plugins/claude.lua 自研适配器），
    -- CLAUDE_BACKEND=plugin（或 options.lua 改 claude_backend 默认）才启用本插件
    return vim.g.ai_assistant == "claude" and vim.g.claude_backend == "plugin"
  end,
  -- 命令注册在 lua/ 而非 plugin/ 目录，lazy 的 shim 自动探测扫不到；
  -- 不声明则插件未加载时 :ClaudeCode 是 E492——agent_sessions 的冷启动
  -- （agent tab 首开 / <leader>an 直按）正走这条路
  cmd = { "ClaudeCode" },
  dependencies = {
    "folke/snacks.nvim",
  },
  config = function(_, opts)
    agent.setup()
    require("claudecode").setup(opts)
  end,
  opts = {
    terminal = {
      provider = provider,
    },
    diff_opts = {
      keep_terminal_focus = true,
    },
  },
  keys = {
    { "<C-a>", function() agent.toggle() end, desc = "Toggle agent pane", mode = { "n", "t" } },
    { "<leader>aa", function() agent.picker() end, desc = "Agent sessions" },
    { "<leader>an", function() agent.new() end, desc = "New agent session" },
    {
      "<leader>aN",
      function()
        vim.ui.input({ prompt = "Session name: " }, function(name)
          if name and name:find("%S") then agent.new(vim.trim(name)) end
        end)
      end,
      desc = "New agent session (named)",
    },
    { "<leader>aC", "<cmd>ClaudeCode --continue<cr>", desc = "Continue Claude" },
    { "<leader>aR", "<cmd>ClaudeCode --resume<cr>", desc = "Resume Claude" },
    { "<leader>aM", "<cmd>ClaudeCodeSelectModel<cr>", desc = "Select Model" },
    {
      "<leader>as",
      function()
        local ft = vim.bo.filetype
        local tree_types = { NvimTree = true, ["neo-tree"] = true, oil = true, minifiles = true, netrw = true }
        if tree_types[ft] then
          send_and_focus("ClaudeCodeTreeAdd")
        elseif vim.fn.mode() == "v" or vim.fn.mode() == "V" or vim.fn.mode() == "\22" then
          send_range_and_focus()
        else
          send_and_focus("ClaudeCodeAdd %")
        end
      end,
      mode = { "n", "v" },
      desc = "Smart Add",
    },
    { "<leader>ada", "<cmd>ClaudeCodeDiffAccept<cr>", desc = "Accept Diff" },
    { "<leader>add", "<cmd>ClaudeCodeDiffDeny<cr>", desc = "Deny Diff" },
  },
}
