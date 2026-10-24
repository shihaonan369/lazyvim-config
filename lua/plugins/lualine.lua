return {
  "nvim-lualine/lualine.nvim",
  opts = function(_, opts)
    -- 主题联动：dracula 时用 dracula.nvim 自带主题（吃 lualine_bg_color
    -- 透底），其余走 auto 派生。lualine 每次 ColorScheme 重跑 setup 现调
    -- 函数；表返回值绕过其 dofile 直载，inactive 改动才落得住
    opts.options = opts.options or {}
    opts.options.theme = function()
      if vim.g.colors_name == "dracula" then
        local t = require("lualine.themes.dracula-nvim")
        -- inactive 段自带纯白实底，与 agent pane 并存时炸眼，统一透掉
        t.inactive.a.bg = "NONE"
        t.inactive.b.bg = "NONE"
        t.inactive.b.fg = t.inactive.a.fg
        t.inactive.c = { fg = t.inactive.a.fg }
        return t
      end
      return "auto"
    end
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
