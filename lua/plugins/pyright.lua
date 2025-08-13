local function get_poetry_python_path()
  local is_windows = package.config:sub(1, 1) == "\\"
  local null_dev = is_windows and "2>NUL" or "2>/dev/null"

  -- 运行命令获取 poetry 虚拟环境路径
  local raw_path = vim.fn.system("poetry env info -p " .. null_dev)
  local path = raw_path:gsub("%s+", "") -- 去除所有空白字符（包括换行）

  if path == "" then
    -- 非 Poetry 项目，返回系统默认 python
    return "python"
  end

  if is_windows then
    return path .. "\\Scripts\\python.exe"
  else
    return path .. "/bin/python"
  end
end

local python_path = get_poetry_python_path()

return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        pyright = {
          settings = {
            python = {
              pythonPath = get_poetry_python_path(),
              analysis = {
                typeCheckingMode = "off",
              },
            },
          },
        },
      },
    },
  },
}
