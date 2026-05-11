local function send_and_focus(cmd)
  vim.cmd(cmd)
  vim.schedule(function()
    vim.cmd("ClaudeCodeFocus")
    vim.schedule(function()
      vim.cmd("startinsert")
    end)
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
    return vim.g.ai_assistant == "claude"
  end,
  dependencies = {
    "folke/snacks.nvim",
  },
  config = true,
  opts = {
    terminal = {
      split_side = "right",
      split_width_percentage = 0.30,
    },
    diff_opts = {
      keep_terminal_focus = true,
    },
  },
  keys = {
    { "<C-a>", "<cmd>ClaudeCode<cr>", desc = "Toggle", mode = { "n", "t" } },
    { "<leader>aa", "<cmd>ClaudeCodeFocus<cr>", desc = "Toggle and focus" },
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
