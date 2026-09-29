return {
  "nvim-lualine/lualine.nvim",
  opts = function(_, opts)
    -- agent session 状态段：每 session 一个图标（状态表情 × 实心/空心
    -- 当前/后台对，与颜色双编码）、pane 收起时全体 robot_off 睡觉。
    -- 渲染与高亮全在 agent_sessions.status() 内（内嵌 %#Group#，
    -- 色取现成主题组自适应明暗），见 docs/adr/0003。
    table.insert(opts.sections.lualine_x, 1, {
      function() return require("agent_sessions").status() end,
      cond = function() return require("agent_sessions").count() > 0 end,
    })
  end,
}
