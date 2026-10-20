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
    -- Smart Add（ADR 0007 层 1）：树节点/选区/整文件 → @引用草稿注入输入框，
    -- 不提交（M.draft，过目后自己 CR）。@path 字面文本 claude 原生理解
    -- （2026-10-20 -p 实证）。选区超 100 行落临时文件改 @tmp 引用，不向
    -- 输入框灌几千行
    local draft_seq = 0
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
      local mode = vim.fn.mode()
      if path == nil and (mode == "v" or mode == "V" or mode == "\22") then
        local l1, l2 = vim.fn.line("'<"), vim.fn.line("'>")
        local lines = vim.fn.getline(l1, l2)
        local fpath = vim.fn.expand("%:p")
        if fpath ~= "" and #lines > 0 then
          if #lines > 100 then
            draft_seq = draft_seq + 1
            local tmp = vim.fn.stdpath("run") .. "/agent-draft-" .. vim.fn.getpid() .. "-" .. draft_seq .. ".txt"
            vim.fn.writefile(lines, tmp)
            return agent.draft("@" .. tmp .. "（选区自 " .. fpath .. " L" .. l1 .. "-L" .. l2 .. "）\n")
          end
          return agent.draft("@" .. fpath .. " L" .. l1 .. "-L" .. l2 .. "：\n" .. table.concat(lines, "\n"))
        end
      end
      path = path or vim.fn.expand("%:p")
      if path == "" then return end
      agent.draft("@" .. path .. " ")
    end, { desc = "Smart Add" })
  end,
}
