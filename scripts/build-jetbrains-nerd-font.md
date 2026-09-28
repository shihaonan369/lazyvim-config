# JetBrainsMono Nerd Font 本地构建记录(2026-09-28)

背景与结论见 docs/adr/0003 已知边界。要点:

- 源材料:JetBrains Mono 官方 TTF(download.jetbrains.com 可达,github 被墙)+
  Hack Nerd Font(原 ~/Library/Fonts,现暂存 ~/fonts-disabled)的 PUA 子集
  (`U+E000-F8FF,U+F0001-F1AF0`,pyftsubset)。
- 合并 = 逐字形移植(RecordingPen 递归解引用组件 → TransformPen 缩放
  1000/2048 upm → TTGlyphPen 重建),**逐字形按包围盒归一化到统一格内尺寸
  (≤0.56em 宽 / ≤0.76em 高)**,hmtx 推进宽度统一钉为 JBM 单格(600)。
  统一性做进字形本身,与渲染路径无关——这是绕开 Ghostty 回退 bug
  (位置相关大小漂移,#1071 同类)的根本手段。
- 产物:JetBrainsMonoNerdFont-{Regular,Bold}.ttf → ~/Library/Fonts,
  ghostty `font-family = JetBrainsMono Nerd Font`。
- 重建流程:下载 JBM → pyftsubset 出 PUA 子集 → 按本文件要点跑移植脚本
  (fontTools)→ 装入字体目录 → Cmd+Q 重启 Ghostty。
