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
      on_colors = function(colors)
        colors.bg_statusline = colors.none
      end,
      on_highlights = function(hl, colors)
        -- noice cmdline 弹窗内衬透明（显式定义）：styles.floats 不覆盖
        -- noice 专属组，tokyonight 也未定义 NoiceCmdlinePopup——回退链落
        -- 到何处不受控（noice 若加默认底色即变实底），显式置 none 锁定
        hl.NoiceCmdlinePopup = { bg = "none", fg = colors.fg }
      end,
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

  {
    "Mofiqul/dracula.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      transparent_bg = true,
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
        retro = "dracula",
        paper = "catppuccin-latte",
      }

      local chosen_theme = theme_map[term_theme] or "tokyonight"

      return {
        colorscheme = chosen_theme,
      }
    end,
  },
}
