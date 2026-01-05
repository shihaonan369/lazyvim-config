-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here
if vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1 then
  vim.opt.shell = "pwsh -NoLogo -ExecutionPolicy RemoteSigned"
  vim.opt.shellcmdflag = "-NoLogo -ExecutionPolicy RemoteSigned -Command"
  vim.opt.shellquote = ""
  vim.opt.shellxquote = ""
else
  vim.opt.shell = "zsh"
end

if vim.env.SSH_CONNECTION or vim.env.DOCKER_EXEC then
  local opts = { noremap = true, silent = true }

  vim.opt.clipboard = (vim.env.SSH_CONNECTION or vim.env.DOCKER_EXEC) and "" or "unnamedplus"
  -- 普通模式复制当前行到 "+ 寄存器
  vim.api.nvim_set_keymap("n", "yy", '"+yy', opts)
  vim.api.nvim_set_keymap("n", "Y", '"+yy', opts)

  -- 可视模式复制选中内容到 "+ 寄存器
  vim.api.nvim_set_keymap("v", "y", '"+y', opts)

  -- 剪切（可选）
  vim.api.nvim_set_keymap("n", "dd", '"+dd', opts)
  vim.api.nvim_set_keymap("v", "d", '"+d', opts)

  -- 普通模式粘贴
  vim.api.nvim_set_keymap("n", "p", '"+p', opts)
  vim.api.nvim_set_keymap("n", "P", '"+P', opts)

  -- 可视模式粘贴
  vim.api.nvim_set_keymap("v", "p", '"+p', opts)
  vim.api.nvim_set_keymap("v", "P", '"+P', opts)
end
