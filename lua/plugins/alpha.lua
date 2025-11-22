local function ensure_chafa_and_redraw(callback)
  -- Already installed
  if vim.fn.executable("chafa") == 1 then
    callback(true)
    return
  end

  vim.notify("chafa not found. Installing...", vim.log.levels.WARN)

  local uname = vim.uv.os_uname().sysname
  local cmd
  local is_windows = false

  if uname == "Darwin" then
    cmd = { "brew", "install", "chafa" }
  elseif uname == "Windows_NT" then
    cmd = { "winget", "install", "chafa" }
    is_windows = true
  else
    vim.notify("Unsupported OS. Please install chafa manually.", vim.log.levels.ERROR)
    callback(false)
    return
  end

  -- Async installation
  vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      if result.code == 0 then
        vim.notify("chafa installed successfully.", vim.log.levels.INFO)
        if is_windows then
          vim.notify("On Windows, you need to restart your terminal for chafa to take effect.", vim.log.levels.WARN)
          callback(false) -- we do not redraw immediately
        else
          callback(true)
        end
      else
        vim.notify("Failed to install chafa:\n" .. result.stderr, vim.log.levels.ERROR)
        callback(false)
      end
    end)
  end)
end

return {
  {
    "goolord/alpha-nvim",
    opts = function(_, opts)
      -- Ensure chafa before generating the terminal header
      ensure_chafa_and_redraw(function(ok)
        require("alpha")
        require("alpha.term")

        opts.opts.opts.noautocmd = true

        local dynamic_header = {
          type = "terminal",
          command = 'chafa -c full --clear --fg-only --symbols braille --size=80x20 "'
            .. vim.fn.stdpath("config")
            .. '/assets/logo.gif"',
          width = 80,
          height = 20,
          opts = {
            position = "center",
            redraw = true,
            window_config = {},
          },
        }

        -- Modify the Alpha layout
        opts.opts.layout[1].val = 2
        opts.opts.layout[2] = dynamic_header

        -- Only redraw automatically on non-Windows systems
        if ok then
          vim.defer_fn(function()
            vim.cmd("AlphaRedraw")
          end, 200)
        end
      end)
    end,
  },
}
