return {
  "akinsho/bufferline.nvim",
  opts = {
    options = {
      -- agent tab 内不列 file buffer 标签（用户裁决 2026-10-15）：agent 域只留
      -- tab 页标签，buffer 条目全滤；离开 tab 恢复。pcall：headless --clean
      -- 测试态 agent_tab 可能缺席
      custom_filter = function(_bufnr)
        local ok, at = pcall(require, "agent_tab")
        if ok and at.active() then return false end
        return true
      end,
      -- 显隐判定交给 config/autocmds.lua 的 tabline_visibility（buffer 数与
      -- tab 数独立计算）：bufferline 自家的 toggle 只数 buffer，单 buffer +
      -- 多 tab 会把装着 tab 标签的整条砍掉
      auto_toggle_bufferline = false,
    },
  },
}
