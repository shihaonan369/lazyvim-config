return {
  "nvim-lualine/lualine.nvim",
  opts = function(_, opts)
    -- agent session 状态段：每 session 一个图标、色 = 状态、当前加方括号、
    -- pane 收起时全体闭眼。渲染与高亮全在 agent_sessions.status() 内
    -- （内嵌 %#Group#，色取现成主题组自适应明暗），见 docs/adr/0003。
    table.insert(opts.sections.lualine_x, 1, {
      function() return require("agent_sessions").status() end,
      cond = function() return require("agent_sessions").count() > 0 end,
    })
  end,
}
