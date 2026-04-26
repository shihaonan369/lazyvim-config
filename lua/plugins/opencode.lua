return {
  "nickjvandyke/opencode.nvim",
  version = "*",
  enabled = function()
    return vim.g.ai_assistant == "opencode"
  end,
  dependencies = {
    {
      "folke/snacks.nvim",
      optional = true,
      opts = {
        input = {},
        picker = {
          actions = {
            opencode_send = function(...)
              return require("opencode").snacks_picker_send(...)
            end,
          },
          win = {
            input = {
              keys = {
                ["<a-a>"] = { "opencode_send", mode = { "n", "i" } },
              },
            },
          },
        },
      },
    },
  },
  keys = {
    {
      "<C-a>",
      function()
        require("opencode").toggle()
      end,
      desc = "Toggle",
      mode = { "n", "t" },
    },
    {
      "<leader>aa",
      function()
        require("opencode").ask("@this: ", { submit = true })
      end,
      desc = "Ask",
      mode = { "n", "x" },
    },
    {
      "<leader>ae",
      function()
        require("opencode").select()
      end,
      desc = "Execute",
      mode = { "n", "x" },
    },
    {
      "<leader>ar",
      function()
        return require("opencode").operator("@this ")
      end,
      desc = "Add Range",
      mode = { "n", "x" },
      expr = true,
    },
    {
      "<leader>al",
      function()
        return require("opencode").operator("@this ") .. "_"
      end,
      desc = "Add Line",
      mode = "n",
      expr = true,
    },
    {
      "<S-C-u>",
      function()
        require("opencode").command("session.half.page.up")
      end,
      desc = "Scroll Up",
    },
    {
      "<S-C-d>",
      function()
        require("opencode").command("session.half.page.down")
      end,
      desc = "Scroll Down",
    },
  },
  config = function()
    vim.g.opencode_opts = {}
    vim.o.autoread = true
    vim.keymap.set("n", "+", "<C-a>", { noremap = true, desc = "Increment number" })
    vim.keymap.set("n", "-", "<C-x>", { noremap = true, desc = "Decrement number" })
  end,
}
