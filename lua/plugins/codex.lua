local function codex_term(args)
  local buf = nil
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(b)
    if name:match("codex$") or name:match("codex ") then
      buf = b
      break
    end
  end

  if buf and vim.api.nvim_buf_is_valid(buf) then
    local wins = vim.fn.win_findbuf(buf)
    if #wins > 0 then
      vim.api.nvim_set_current_win(wins[1])
      vim.cmd("startinsert")
      return
    end
    -- buffer exists but window closed, delete it and reopen
    vim.api.nvim_buf_delete(buf, { force = true })
  end

  Snacks.terminal.open({ "codex", unpack(args) }, {
    win = {
      position = "right",
      width = 0.30,
    },
  })
end

local function send_and_focus(cmd)
  local buf = nil
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(b)
    if name:match("codex$") or name:match("codex ") then
      buf = b
      break
    end
  end
  if not buf then
    codex_term({})
    buf = nil
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      local name = vim.api.nvim_buf_get_name(b)
      if name:match("codex$") or name:match("codex ") then
        buf = b
        break
      end
    end
  end
  if not buf then return end

  local chan = vim.b[buf].terminal_job_id
  if chan then
    vim.api.nvim_chan_send(chan, cmd .. "\n")
  end
  vim.schedule(function()
    local wins = vim.fn.win_findbuf(buf)
    if #wins > 0 then
      vim.api.nvim_set_current_win(wins[1])
      vim.cmd("startinsert")
    end
  end)
end

return {
  "util/codex.nodata", -- virtual plugin, no actual download
  lazy = true,
  enabled = function()
    return vim.g.ai_assistant == "codex"
  end,
  config = function()
    vim.keymap.set({ "n", "t" }, "<C-a>", function() codex_term({}) end, { desc = "Toggle Codex" })
    vim.keymap.set("n", "<leader>aa", function() codex_term({}) end, { desc = "Toggle Codex" })
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
      send_and_focus(path)
    end, { desc = "Smart Add" })
  end,
}
