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
      lualine_bg_color = "NONE", -- 官方旋钮：dracula-nvim lualine 主题 b/c 段透底
      -- 对齐 tokyonight 的透明面：chrome/浮层不实底，交互高亮（cursorline/
      -- visual/search…）保留。overrides 函数形式是插件官方扩展点
      overrides = function(colors)
        return {
          StatusLine = { fg = colors.white }, -- 状态栏（lualine auto 主题据此透底）
          StatusLineTerm = { fg = colors.white },
          WinBar = { fg = colors.white }, -- nvim 内置默认带 #07080d 实底
          WinBarNC = { fg = colors.white },
          TabLineFill = {}, -- bufferline 背后衬底
          NormalFloat = { fg = colors.fg }, -- 浮层底窗（lazy/noice/picker）
          MsgSeparator = { fg = colors.comment },
          Terminal = { fg = colors.white }, -- :terminal 空白区
          SnacksBackdrop = {}, -- dashboard 背后整屏压暗层
          -- 同 tokyonight：noice 专属组，显式锁透明防回退链落实底
          NoiceCmdlinePopup = { bg = "NONE", fg = colors.fg },
        }
      end,
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
