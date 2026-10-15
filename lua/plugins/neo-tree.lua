return {
  "nvim-neo-tree/neo-tree.nvim",
  opts = function(_, opts)
    -- agent_tree 是外部源（lua/agent_tree.lua，agent tab 左侧列表，ADR 0005）。
    -- sources 必须追加而非赋值：lazy 合并 opts 时数组是整体替换，
    -- 直接写 sources={"agent_tree"} 会替掉 LazyVim 默认三源（filesystem/
    -- buffers/git_status），<leader>e 即失效
    opts.sources = opts.sources or {}
    table.insert(opts.sources, "agent_tree")
    -- neo-tree 默认 + LazyVim 全局 window.mappings 会并入每个源；文件类命令
    -- （open/preview/split/close_node…）在 agent_tree 无实现，按一次报一次。
    -- per-source 的 user 层优先级最高，逐个 "none" 禁用
    opts.agent_tree = {
      window = {
        mappings = {
          ["l"] = "none",
          ["h"] = "none",
          ["P"] = "none",
          ["z"] = "none",
          ["Z"] = "none",
          ["o"] = "none",
          ["O"] = "none",
          ["s"] = "none",
          ["S"] = "none",
          ["Y"] = "none",
          ["gy"] = "none",
          ["c"] = "none",
          ["m"] = "none",
          ["r"] = "none",
          ["A"] = "none",
          ["w"] = "none",
          ["<C-s>"] = "none",
          ["<"] = "none",
          [">"] = "none",
          ["<C-;>"] = "none",
          ["<C-b>"] = "none",
          ["<C-f>"] = "none",
          ["<C-r>"] = "none",
          ["<Tab>"] = "none",
          ["C"] = "none",
          ["e"] = "none",
          ["p"] = "none",
          ["t"] = "none",
          ["T"] = "none",
          ["u"] = "none",
          ["U"] = "none",
          ["x"] = "none",
          ["y"] = "none",
        },
      },
    }
    opts.filesystem = vim.tbl_deep_extend("force", opts.filesystem or {}, {
      filtered_items = {
        visible = true,
      },
    })
  end,
}
