-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

-- Disable autoformat for lua files
vim.api.nvim_create_autocmd({ "FileType" }, {
  pattern = { "python", "java" },
  callback = function()
    vim.b.autoformat = false
  end,
})

-- markdown 默认关闭 wrap（覆盖 LazyVim 的 lazyvim_wrap_spell 默认行为）
vim.api.nvim_create_autocmd({ "FileType" }, {
  pattern = { "markdown" },
  callback = function()
    vim.opt_local.wrap = false
  end,
})

-- tabline 显隐独立计算：buffer 数与 tab 数任一 >1 即显示（用户裁决
-- 2026-10-15，docs/adr/0005 的 bufferline 过滤配套）。接管 bufferline 的
-- toggle_bufferline——它只数 buffer，单 buffer + 多 tab 时会把整条砍掉，
-- tab 段的存亡被 buffer 段绑架；auto_toggle_bufferline=false 见
-- lua/plugins/bufferline.lua
vim.api.nvim_create_augroup("tabline_visibility", { clear = true })
vim.api.nvim_create_autocmd({ "BufAdd", "BufDelete", "TabNew", "TabClosed", "TabEnter" }, {
  group = "tabline_visibility",
  callback = function()
    local show = #vim.fn.getbufinfo({ buflisted = 1 }) > 1 or #vim.api.nvim_list_tabpages() > 1
    vim.o.showtabline = show and 2 or 0
  end,
})
