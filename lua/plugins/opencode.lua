return {
  "nickjvandyke/opencode.nvim",
  version = "*",
  enabled = function()
    return vim.g.ai_assistant == "opencode"
  end,
  dependencies = {
    {
      "folke/snacks.nvim",
      optional = true,
      opts = {
        input = {},
        picker = {
          actions = {
            opencode_send = function(...)
              return require("opencode").snacks_picker_send(...)
            end,
          },
          win = {
            input = {
              keys = {
                ["<a-a>"] = { "opencode_send", mode = { "n", "i" } },
              },
            },
          },
        },
      },
    },
  },
  keys = (function()
    local focus_opencode = function()
      vim.defer_fn(function()
        for _, win in ipairs(vim.api.nvim_list_wins()) do
          local buf = vim.api.nvim_win_get_buf(win)
          if vim.bo[buf].buftype == "terminal" then
            local name = vim.api.nvim_buf_get_name(buf)
            if name:match("opencode") then
              vim.api.nvim_set_current_win(win)
              vim.cmd("startinsert")
              break
            end
          end
        end
      end, 100)
    end

    return {
      {
        "<C-a>",
        function()
          require("opencode").toggle()
        end,
        desc = "Toggle",
        mode = { "n", "t" },
      },
      {
        "<leader>aa",
        function()
          require("opencode").ask("@this: ", { submit = true })
        end,
        desc = "Ask",
        mode = { "n", "x" },
      },
      {
        "<leader>ae",
        function()
          require("opencode").select()
        end,
        desc = "Execute",
        mode = { "n", "x" },
      },
      {
        "<leader>as",
        function()
          local mode = vim.fn.mode()
          if mode == "v" or mode == "V" or mode == "\x16" then
            local start = vim.fn.getpos("'<")
            local end_ = vim.fn.getpos("'>")
            if start[2] == end_[2] and start[3] == end_[3] then
              local result = require("opencode").operator("@this ") .. "_"
              focus_opencode()
              return result
            end
            local result = require("opencode").operator("@this ")
            focus_opencode()
            return result
          end

          local ft = vim.bo.filetype
          local path
          if ft == "neo-tree" then
            local ok, neotree = pcall(require, "neo-tree.sources.manager")
            if ok then
              local state = neotree.get_state("filesystem")
              if state and state.tree then
                ---@diagnostic disable-next-line: undefined-field
                local node = state.tree:get_node()
                if node then
                  path = node.path or node:get_id()
                end
              end
            end
          elseif ft == "NvimTree" then
            local ok, api = pcall(require, "nvim-tree.api")
            if ok then
              path = api.tree.get_node_under_cursor().absolute_path
            end
          elseif ft == "oil" then
            local ok, oil = pcall(require, "oil")
            if ok then
              local dir = oil.get_current_dir()
              if dir then
                path = dir .. vim.fn.expand("%:t")
              end
            end
          end
          path = path or vim.fn.expand("%:p")
          require("opencode").prompt(path .. " ", { submit = false })
          focus_opencode()
          return ""
        end,
        mode = { "n", "v", "x" },
        desc = "Smart Add",
        expr = true,
      },
      {
        "<leader>aC",
        function()
          ---@diagnostic disable-next-line: undefined-field
          require("opencode.server").get():next(function(server)
            server:get_sessions(function(sessions)
              if sessions and #sessions > 0 then
                table.sort(sessions, function(a, b)
                  return a.time.updated > b.time.updated
                end)
                server:select_session(sessions[1].id)
                focus_opencode()
              else
                vim.notify("No sessions found", vim.log.levels.WARN, { title = "opencode" })
              end
            end)
          end)
        end,
        desc = "Continue",
      },
      {
        "<leader>aR",
        function()
          require("opencode").select_session():next(function()
            focus_opencode()
          end)
        end,
        desc = "Resume",
      },
    }
  end)(),
  config = function()
    vim.g.opencode_opts = {}
    vim.o.autoread = true
    vim.keymap.set("n", "+", "<C-a>", { noremap = true, desc = "Increment number" })
    vim.keymap.set("n", "-", "<C-x>", { noremap = true, desc = "Decrement number" })
  end,
}
