return {
  {
    "snacks.nvim",
    opts = {
      terminal = {
        win = {
          keys = {
            hide_slash = false,
            hide_underscore = false,
          },
        },
      },
      picker = {
        actions = {
          -- pick_win 显式选目标；选中 agent pane 时向其报备放行一次（docs/adr/0002）
          agent_pick = function(picker)
            if Snacks.picker.actions.pick_win(picker) then return end
            local win = picker.main
            if win and vim.api.nvim_win_is_valid(win) and vim.w[win].agent_pane then
              require("agent_sessions").arm_override()
            end
            return Snacks.picker.actions.jump(picker)
          end,
        },
        win = {
          input = { keys = { ["<S-CR>"] = { "agent_pick", mode = { "n", "i" } } } },
          list = { keys = { ["<S-CR>"] = { "agent_pick" } } },
        },
      },
    },
  },
}
