return {
  {
    "folke/tokyonight.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      style = "night",
      transparent = true,
      styles = {
        sidebars = "transparent",
        floats = "transparent",
      },
    },
  },
  {
    "scottmckendry/cyberdream.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      transparent = true,
    },
  },
  {
    "catppuccin/nvim",
    lazy = false,
    priority = 1000,
    opts = {
      transparent_background = true,
      float = {
        transparent = true,
        solid = false,
      },
    },
  },

  -- Configure LazyVim to load theme based on TERMINAL_THEME
  {
    "LazyVim/LazyVim",
    opts = function()
      -- 读取环境变量，不区分大小写
      local term_theme = os.getenv("TERMINAL_THEME")
      if term_theme then
        term_theme = term_theme:lower()
      end

      local theme_map = {
        retro = "tokyonight",
        paper = "catppuccin",
      }

      local chosen_theme = theme_map[term_theme] or "tokyonight"

      return {
        colorscheme = chosen_theme,
      }
    end,
  },
}
