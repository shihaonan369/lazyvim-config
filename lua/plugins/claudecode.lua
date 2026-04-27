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
    { "<leader>ab", "<cmd>ClaudeCodeAdd %<cr>", desc = "Add Buffer" },
    {
      "<leader>al",
      ":.ClaudeCodeSend<CR>",
      desc = "Add Line",
    },
    {
      "<leader>ar",
      ":'<,'>ClaudeCodeSend<CR>",
      mode = "v",
      desc = "Add Range",
    },
    {
      "<leader>af",
      "<cmd>ClaudeCodeTreeAdd<cr>",
      desc = "Add file",
      ft = { "NvimTree", "neo-tree", "oil", "minifiles", "netrw" },
    },
    { "<leader>ada", "<cmd>ClaudeCodeDiffAccept<cr>", desc = "Accept Diff" },
    { "<leader>add", "<cmd>ClaudeCodeDiffDeny<cr>", desc = "Deny Diff" },
  },
}
