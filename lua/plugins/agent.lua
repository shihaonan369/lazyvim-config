local agent = require("agent_sessions")

-- agent 工作台本地 spec（**唯一的 dir spec**，ADR 0007）：lazy.nvim 会把
-- 同 dir 的多个 spec 合并成一个裁决者——此前 claude-config 与 codex-config
-- 同指 stdpath("config")，claude 态双双消失（"只有 agent tab 没有 pane"，
-- 2026-10-21 案；codex 态恰好幸存是因合并裁决者落在 codex 侧）。四家分流：
-- claude native / codex / pi 在此接线；claude plugin 态（CLAUDE_BACKEND=
-- plugin）交给 claudecode.nvim；opencode 走 plugins/opencode.lua。

local function claude_native()
  return vim.g.ai_assistant == "claude" and vim.g.claude_backend ~= "plugin"
end

return {
  dir = vim.fn.stdpath("config"),
  name = "agent-config",
  enabled = function()
    if vim.g.ai_assistant == "codex" then return true end
    if vim.g.ai_assistant == "pi" then return true end
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

    -- Smart Add：树感知 path 提取共用；Visual 模式附加选区行范围；claude native
    -- 构造 @引用草稿（M.draft，不提交，过目后自己 CR）。行范围用
    -- @path:l1-l2 /
    -- @path:l（2026-10-21 -p 实证：范围生效、范围后换行正文不干扰）；
    -- **选区原文不随发**——claude 按范围自己读盘，超长选区同样只是范围引用
    -- （用户裁决 2026-10-21）；codex 发送路径及范围
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
      -- pi：@ 弹窗是交互式文件搜索（G2 实证粘贴 @ 落为纯文本、不触发附件），
      -- 无行区间引用语法——草稿纯文本 path:行范围（pi 用 read 工具按行取），
      -- 不提交、过目后自己 CR（与 claude native 的 draft 隐喻同款）
      if vim.g.ai_assistant == "pi" then
        local range = ""
        if path == nil and (mode == "v" or mode == "V" or mode == "\22") then
          local l1, l2 = vim.fn.line("'<"), vim.fn.line("'>")
          local fpath = vim.fn.expand("%:p")
          if fpath ~= "" and l1 > 0 and l2 >= l1 then
            range = (l1 == l2) and (":" .. l1) or (":" .. l1 .. "-" .. l2)
            path = fpath
          end
        end
        path = path or vim.fn.expand("%:p")
        if path == "" then return end
        agent.draft(path .. range .. " ")
        return
      end
      if not claude_native() then
        local line_range = ""
        if path == nil and (mode == "v" or mode == "V" or mode == "\22") then
          local l1, l2 = vim.fn.line("v"), vim.fn.line(".")
          if l1 > l2 then l1, l2 = l2, l1 end
          local fpath = vim.fn.expand("%:p")
          if fpath ~= "" and l1 > 0 and l2 >= l1 then
            line_range = (l1 == l2) and tostring(l1) or (l1 .. "-" .. l2)
            path = fpath
          end
        end
        path = path or vim.fn.expand("%:p")
        if line_range ~= "" then
          local codex_range = "#L" .. line_range:gsub("(%d+)%-(%d+)", "%1-L%2")
          path = "@" .. path .. codex_range
        end
        agent.send(path)
        return
      end
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

    -- codex 专属（aC/aR/aM 键位面与 claude native 同构，2026-10-30 审计后
    -- 平移）：aC/aR = codex resume（--last≈--continue 的 cwd 最近、无参=TUI
    -- 原生 picker）；aM = /model 注入（M.command 后端中立，codex TUI 原生
    -- /model 弹 picker，0.166 官方斜杠命令表核实）
    if vim.g.ai_assistant == "codex" then
      vim.keymap.set("n", "<leader>aC", function() agent.resume("last") end,
        { desc = "Continue (cwd-recent)" })
      vim.keymap.set("n", "<leader>aR", function() agent.resume("picker") end, { desc = "Resume (picker)" })
      vim.keymap.set("n", "<leader>aM", function()
        local id = agent.current_id()
        if id then agent.command(id, "/model") end
      end, { desc = "Model picker" })
    end

    -- pi 专属（同 codex 形状）：aC = --continue（cwd 最近）、aR = TUI 原生
    -- --resume 选择器；aM = /model 注入（usage.md 核实，Ctrl+L 同效）；
    -- inline diff 同 claude native 接线——快照由机器侧 pi 扩展
    -- （~/.pi/agent/extensions/agent-diff.ts）落同一 AGENT_DIFF_DIR 布局，
    -- agent_diff.lua 后端中立零改动复用
    if vim.g.ai_assistant == "pi" then
      vim.keymap.set("n", "<leader>aC", function() agent.resume("last") end,
        { desc = "Continue (cwd-recent)" })
      vim.keymap.set("n", "<leader>aR", function() agent.resume("picker") end, { desc = "Resume (picker)" })
      vim.keymap.set("n", "<leader>aM", function()
        local id = agent.current_id()
        if id then agent.command(id, "/model") end
      end, { desc = "Model picker" })
      local diff = require("agent_diff")
      diff.setup()
      vim.keymap.set("n", "<leader>ad", function() diff.review_picker() end, { desc = "Review agent diffs" })
      vim.keymap.set("n", "<leader>ada", function() diff.accept() end, { desc = "Accept diff" })
      vim.keymap.set("n", "<leader>add", function() diff.deny() end, { desc = "Deny (rollback) diff" })
    end

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
