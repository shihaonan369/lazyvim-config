#!/bin/bash

# ========== 参数解析 ==========
if [ "$#" -lt 2 ]; then
  echo "Usage: $0 <input.mp4> <output_dir> [fps=24] [scale_width=80]"
  exit 1
fi

INPUT="$1"
OUTDIR="$2"
FPS="${3:-24}"         # 默认帧率 24
SCALE_WIDTH="${4:-80}" # 默认宽度 80，自动等比缩放高度
TMPDIR=$(mktemp -d)

# ========== 自动清理 ==========
cleanup() {
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

# ========== 创建输出目录 ==========
mkdir -p "$OUTDIR"

echo "📽️  Step 1: 拆帧中 (fps=$FPS, width=$SCALE_WIDTH)..."
ffmpeg -loglevel error -i "$INPUT" -vf "fps=${FPS},scale=${SCALE_WIDTH}:-1:flags=lanczos" "$TMPDIR/frame_%05d.png"

echo "🎨  Step 2: 渲染字符帧中..."
for f in "$TMPDIR"/frame_*.png; do
  FRAME_NAME=$(basename "${f%.png}.txt")
  chafa "$f" --format=ansi --symbols=ascii --fg-only >"$OUTDIR/$FRAME_NAME"
done

echo "✅ 完成！已输出到：$OUTDIR"
