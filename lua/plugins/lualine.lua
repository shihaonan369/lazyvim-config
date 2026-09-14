return {
  "nvim-lualine/lualine.nvim",
  opts = function(_, opts)
    table.insert(opts.sections.lualine_x, 1, {
      function()
        local A = require("agent_sessions")
        local text = A.status()
        if text ~= "" and not A.pane_visible() then
          -- 闭眼（nf-md-eye_off）：pane 收起，session 在后台
          text = vim.fn.nr2char(0xF0209) .. " " .. text
        end
        return text
      end,
      cond = function() return require("agent_sessions").count() > 0 end,
      color = "Keyword",
    })
  end,
}
