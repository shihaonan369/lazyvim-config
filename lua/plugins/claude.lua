local agent = require("agent_sessions")

-- claude 原生后端（ADR 0007）：claudecode.nvim 的本仓替代，与 codex.lua 同构
-- 的本地 dir spec。磨合期与插件并存：CLAUDE_BACKEND=plugin（或 options.lua 改
-- claude_backend 默认）时本 spec 失活、claudecode.lua 接管，一键回今天的行为。
return {
  dir = vim.fn.stdpath("config"),
  name = "claude-config",
  enabled = function()
    return vim.g.ai_assistant == "claude" and vim.g.claude_backend ~= "plugin"
  end,
  config = function()
    agent.setup()
    vim.keymap.set({ "n", "t" }, "<C-a>", function() agent.toggle() end, { desc = "Toggle agent pane" })
    vim.keymap.set("n", "<leader>aa", function() agent.picker() end, { desc = "Agent sessions" })
    vim.keymap.set("n", "<leader>an", function() agent.new() end, { desc = "New agent session" })
    vim.keymap.set("n", "<leader>aN", function()
      vim.ui.input({ prompt = "Session name: " }, function(name)
        if name and name:find("%S") then agent.new(vim.trim(name)) end
      end)
    end, { desc = "New agent session (named)" })
    -- --continue 的"最近"以 cwd 为界（CLI 语义），与 session 池的"最近"是两个
    -- 概念；-r 无值时 TUI 内开原生会话 picker，零 nvim 侧代码。均新建 session
    vim.keymap.set("n", "<leader>aC", function() agent.claude_open("claude --continue") end,
      { desc = "Continue (cwd-recent)" })
    vim.keymap.set("n", "<leader>aR", function() agent.claude_open("claude -r") end,
      { desc = "Resume (picker)" })
    -- /model 在 TUI 内开选择 UI；rename 同款注入序列（M.command）
    vim.keymap.set("n", "<leader>aM", function()
      local id = agent.current_id()
      if id then agent.command(id, "/model") end
    end, { desc = "Model picker" })
    -- Smart Add（层 1 前的桩形态，ADR 0007）：树感知 path 提取同 codex.lua，
    -- 注入 @引用草稿进输入框、不提交（M.send submit=false），过目后自己 CR；
    -- 选区富语义（行号范围/括号粘贴/超长落临时文件）由后续层补全
    vim.keymap.set({ "n", "v" }, "<leader>as", function()
      local ft = vim.bo.filetype
      local tree_types = { NvimTree = true, ["neo-tree"] = true, oil = true, minifiles = true, netrw = true }
      local path
      if tree_types[ft] then
        if ft == "neo-tree" then
          local ok, neotree = pcall(require, "neo-tree.sources.manager")
          if ok then
            local state = neotree.get_state("filesystem")
            if state and state.tree then
              local node = state.tree:get_node()
              if node then path = node.path or node:get_id() end
            end
          end
        elseif ft == "NvimTree" then
          local ok, api = pcall(require, "nvim-tree.api")
          if ok then path = api.tree.get_node_under_cursor().absolute_path end
        elseif ft == "oil" then
          local ok, oil = pcall(require, "oil")
          if ok then
            local dir = oil.get_current_dir()
            if dir then path = dir .. vim.fn.expand("%:t") end
          end
        end
      end
      path = path or vim.fn.expand("%:p")
      agent.send("@" .. path .. " ", false)
    end, { desc = "Smart Add" })
  end,
}
