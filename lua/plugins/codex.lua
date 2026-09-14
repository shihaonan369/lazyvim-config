local agent = require("agent_sessions")

return {
  dir = vim.fn.stdpath("config"),
  name = "codex-config",
  enabled = function()
    return vim.g.ai_assistant == "codex"
  end,
  config = function()
    agent.setup()
    vim.keymap.set({ "n", "t" }, "<C-a>", function() agent.toggle() end, { desc = "Toggle agent pane" })
    vim.keymap.set("n", "<leader>aa", function() agent.picker() end, { desc = "Agent sessions" })
    vim.keymap.set("n", "<leader>an", function() agent.new() end, { desc = "New agent session" })
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
      agent.send(path)
    end, { desc = "Smart Add" })
  end,
}
