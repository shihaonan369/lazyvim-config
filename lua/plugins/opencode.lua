return {
  "nickjvandyke/opencode.nvim",
  version = "*", -- Latest stable release
  dependencies = {
    {
      -- `snacks.nvim` integration is recommended, but optional
      ---@module "snacks" <- Loads `snacks.nvim` types for configuration intellisense
      "folke/snacks.nvim",
      optional = true,
      opts = {
        input = {}, -- Enhances `ask()`
        picker = { -- Enhances `select()`
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
  config = function()
    ---@type opencode.Opts
    vim.g.opencode_opts = {
      -- Your configuration, if any; goto definition on the type or field for details
    }

    vim.o.autoread = true -- Required for `opts.events.reload`

    local op = require("opencode")

    -- toggle (快速键)
    vim.keymap.set({ "n", "t" }, "<C-a>", function()
      op.toggle()
    end, { desc = "Toggle opencode" })

    -- ask
    vim.keymap.set({ "n", "x" }, "<leader>aa", function()
      op.ask("@this: ", { submit = true })
    end, { desc = "Opencode Ask" })

    -- execute action
    vim.keymap.set({ "n", "x" }, "<leader>ae", function()
      op.select()
    end, { desc = "Opencode Execute" })

    -- add range
    vim.keymap.set({ "n", "x" }, "<leader>ar", function()
      return op.operator("@this ")
    end, { expr = true, desc = "Opencode Add Range" })

    -- add current line
    vim.keymap.set("n", "<leader>al", function()
      return op.operator("@this ") .. "_"
    end, { expr = true, desc = "Opencode Add Line" })

    -- scroll up
    vim.keymap.set("n", "<S-C-u>", function()
      op.command("session.half.page.up")
    end, { desc = "Opencode Scroll Up" })

    -- scroll down
    vim.keymap.set("n", "<S-C-d>", function()
      op.command("session.half.page.down")
    end, { desc = "Opencode Scroll Down" })

    vim.keymap.set("n", "+", "<C-a>", { noremap = true, desc = "Increment number" })
    vim.keymap.set("n", "-", "<C-x>", { noremap = true, desc = "Decrement number" })
  end,
}
