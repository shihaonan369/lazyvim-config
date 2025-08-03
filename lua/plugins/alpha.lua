return {
  {
    "goolord/alpha-nvim",
    opts = function(_, opts)
      require("alpha")
      require("alpha.term")
      local play_ascii_frames = vim.fn.stdpath("config") .. "/scripts/play_ascii_frames.sh"
      local ascii_logo_frames = vim.fn.stdpath("config") .. "/assets/ascii_logo_frames"
      opts.opts.opts.noautocmd = true
      local dynamic_header = {
        type = "terminal",
        command = "chmod +x " .. play_ascii_frames .. " && " .. play_ascii_frames .. " " .. ascii_logo_frames .. " 60",
        width = 40,
        height = 20,
        opts = {
          position = "center",
          redraw = true,
          window_config = {},
        },
      }

      opts.opts.layout[1].val = 2
      opts.opts.layout[2] = dynamic_header

      vim.defer_fn(function()
        vim.cmd("AlphaRedraw")
      end, 100)
    end,
  },
}
