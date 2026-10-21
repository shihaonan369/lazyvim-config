local agent = require("agent_sessions")

-- agent 工作台本地 spec（**唯一的 dir spec**，ADR 0007）：lazy.nvim 会把
-- 同 dir 的多个 spec 合并成一个裁决者——此前 claude-config 与 codex-config
-- 同指 stdpath("config")，claude 态双双消失（"只有 agent tab 没有 pane"，
-- 2026-10-21 案；codex 态恰好幸存是因合并裁决者落在 codex 侧）。三家分流：
-- claude native / codex 在此接线；claude plugin 态（CLAUDE_BACKEND=plugin）
-- 交给 claudecode.nvim；opencode 走 plugins/opencode.lua。

local function claude_native()
  return vim.g.ai_assistant == "claude" and vim.g.claude_backend ~= "plugin"
end

return {
  dir = vim.fn.stdpath("config"),
  name = "agent-config",
  enabled = function()
    if vim.g.ai_assistant == "codex" then return true end
    return claude_native()
  end,
  config = function()
    agent.setup()
    -- 三家同构的核心键位
    vim.keymap.set({ "n", "t" }, "<C-a>", function() agent.toggle() end, { desc = "Toggle agent pane" })
    vim.keymap.set("n", "<leader>aa", function() agent.picker() end, { desc = "Agent sessions" })
    vim.keymap.set("n", "<leader>an", function() agent.new() end, { desc = "New agent session" })
    vim.keymap.set("n", "<leader>aN", function()
      vim.ui.input({ prompt = "Session name: " }, function(name)
        if name and name:find("%S") then agent.new(vim.trim(name)) end
      end)
    end, { desc = "New agent session (named)" })

    -- Smart Add：树感知 path 提取共用；claude native 构造 @引用草稿（M.draft，
    -- 不提交，过目后自己 CR）。行范围用 claude 原生语法 @path:l1-l2 /
    -- @path:l（2026-10-21 -p 实证：范围生效、范围后换行正文不干扰）；
    -- **选区原文不随发**——claude 按范围自己读盘，超长选区同样只是范围引用
    -- （用户裁决 2026-10-21）；codex 维持纯路径投喂
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
      if not claude_native() then
        path = path or vim.fn.expand("%:p")
        agent.send(path)
        return
      end
      local mode = vim.fn.mode()
      if path == nil and (mode == "v" or mode == "V" or mode == "\22") then
        local l1, l2 = vim.fn.line("'<"), vim.fn.line("'>")
        local fpath = vim.fn.expand("%:p")
        if fpath ~= "" and l1 > 0 and l2 >= l1 then
          local range = (l1 == l2) and (":" .. l1) or (":" .. l1 .. "-" .. l2)
          return agent.draft("@" .. fpath .. range .. " ")
        end
      end
      path = path or vim.fn.expand("%:p")
      if path == "" then return end
      agent.draft("@" .. path .. " ")
    end, { desc = "Smart Add" })

    -- claude native 专属（ADR 0007 层 0a/1/2）
    if claude_native() then
      -- --continue 的"最近"以 cwd 为界（CLI 语义），与 session 池的"最近"是两个
      -- 概念；-r 无值时 TUI 内开原生会话 picker，零 nvim 侧代码。均新建 session
      vim.keymap.set("n", "<leader>aC", function() agent.claude_open("claude --continue") end,
        { desc = "Continue (cwd-recent)" })
      vim.keymap.set("n", "<leader>aR", function() agent.claude_open("claude -r") end, { desc = "Resume (picker)" })
      -- /model 在 TUI 内开选择 UI；rename 同款注入序列（M.command）
      vim.keymap.set("n", "<leader>aM", function()
        local id = agent.current_id()
        if id then agent.command(id, "/model") end
      end, { desc = "Model picker" })
      -- inline diff 审阅（先落后审）：ad=待审清单（存活 session 的回合基线
      -- 快照），ada=接受（留盘），add=回滚到回合基线
      local diff = require("agent_diff")
      diff.setup()
      vim.keymap.set("n", "<leader>ad", function() diff.review_picker() end, { desc = "Review agent diffs" })
      vim.keymap.set("n", "<leader>ada", function() diff.accept() end, { desc = "Accept diff" })
      vim.keymap.set("n", "<leader>add", function() diff.deny() end, { desc = "Deny (rollback) diff" })
      -- :ClaudeCode 肌肉记忆兼容（ADR 0001 契约面）：无参=新建，带参透传
      vim.api.nvim_create_user_command("ClaudeCode", function(opts)
        local args = vim.trim(opts.args or "")
        if args == "" then
          agent.new()
        else
          agent.claude_open("claude " .. args)
        end
      end, { nargs = "?", desc = "agent pane claude（native 兼容入口）" })
    end
  end,
}
