if vim.g.vscode then
  local vscode = require("vscode")
  -- keybindings
  vim.keymap.set("n", "gi", function()
    vscode.action("editor.action.goToImplementation")
  end)
  vim.keymap.set("n", "gI", function()
    vscode.action("editor.action.peekImplementation")
  end)
else
  -- bootstrap lazy.nvim, LazyVim and your plugins
  require("config.lazy")
end
