return {
  {
    "folke/tokyonight.nvim",
    opts = {
      style = "night",
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
    opts = {
      transparent_background = true,
      float = {
        transparent = true,
        solid = false,
      },
    },
  },

  -- Configure LazyVim to load theme
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "catppuccin",
    },
  },
}
