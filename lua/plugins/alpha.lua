return {
  {
    "goolord/alpha-nvim",
    opts = function(_, opts)
      require("alpha")
      require("alpha.term")
      opts.opts.opts.noautocmd = true
      local dynamic_header = {
        type = "terminal",
        command = 'chafa -c full --clear --fg-only --symbols braille --size=80x20 "'
          .. vim.fn.stdpath("config")
          .. '/assets/logo.gif"',
        width = 80,
        height = 21,
        opts = {
          position = "center",
          redraw = true,
          window_config = {},
        },
      }

      opts.opts.layout[2] = dynamic_header

      vim.defer_fn(function()
        vim.cmd("AlphaRedraw")
      end, 100)
    end,
  },
}
